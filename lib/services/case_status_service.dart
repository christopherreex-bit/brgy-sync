import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/budget_health.dart';
import '../utils/budget_period.dart';
import '../utils/constants.dart';

class CaseStatusService {
  final FirebaseFirestore _db;

  CaseStatusService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<void> updateStatus({
    required String caseId,
    required String newStatus,
    required String notes,
    required String staffId,
    required String staffName,
    required String staffRole,
    String? referenceNumber,
    bool smsSent = false,
    String? smsError,
    String smsBody = '',
    DateTime? changedAt,
    bool budgetApprovalConfirmed = false,
    double? approvedAssistanceAmount,
  }) async {
    final effectiveDate = changedAt ?? DateTime.now();
    final caseRef = _db.collection('cases').doc(caseId);
    final initialCase = await caseRef.get();
    if (!initialCase.exists) throw StateError('Case not found.');

    final initialData = initialCase.data()!;
    DocumentReference<Map<String, dynamic>>? programRef;

    if (newStatus == statusApproved && _requiresBudgetReview(initialData)) {
      final programName = budgetProgramNameForCase(
        (initialData['serviceCategory'] ?? '').toString(),
        (initialData['serviceSubType'] ?? '').toString(),
      );
      if (programName == null) {
        throw StateError(
          'No budget program mapping exists for this assistance case type.',
        );
      }
      programRef = await _findQuarterlyProgram(programName, effectiveDate);
      if (programRef == null) {
        final quarter = quarterForDate(effectiveDate);
        throw StateError(
          'No $programName allocation exists for '
          'FY ${effectiveDate.year} Q$quarter.',
        );
      }
    } else if ((newStatus == statusReleased || newStatus == statusRejected) &&
        (initialData['budgetReservedProgramId'] ?? '').toString().isNotEmpty) {
      programRef = _db
          .collection('budgetPrograms')
          .doc(initialData['budgetReservedProgramId'].toString());
    } else if (_requiresBudgetDeduction(initialData, newStatus)) {
      final programName = budgetProgramNameForCase(
        (initialData['serviceCategory'] ?? '').toString(),
        (initialData['serviceSubType'] ?? '').toString(),
      );
      programRef = programName == null
          ? null
          : await _findQuarterlyProgram(programName, effectiveDate);
    }

    final logRef = caseRef.collection('actionLog').doc();
    final budgetTransactionRef = _db
        .collection('budgetTransactions')
        .doc(caseId);

    await _db.runTransaction((transaction) async {
      final currentCase = await transaction.get(caseRef);
      if (!currentCase.exists) throw StateError('Case not found.');

      final caseData = currentCase.data()!;
      final previousStatus = (caseData['status'] ?? '').toString();
      if (!validNextCaseStatuses(previousStatus).contains(newStatus)) {
        throw StateError(
          'Cannot change status from '
          '${caseStatusLabel(previousStatus)} to ${caseStatusLabel(newStatus)}.',
        );
      }
      if (newStatus == statusForClaiming && staffRole != roleCaptain) {
        throw StateError(
          'Barangay Captain approval is required before a case can move to '
          'For Claiming.',
        );
      }
      if (newStatus == statusApproved &&
          _requiresBudgetReview(caseData) &&
          !budgetApprovalConfirmed) {
        throw StateError(
          'Review and confirm the budget impact before approving this case.',
        );
      }
      final updates = <String, dynamic>{
        'status': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (newStatus == statusForClaiming) {
        updates.addAll({
          'claimingApprovalStatus': 'approved',
          'claimingApprovedBy': staffId,
          'claimingApprovedByName': staffName,
          'claimingApprovedAt': FieldValue.serverTimestamp(),
        });
      }
      final category = (caseData['serviceCategory'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (newStatus == statusApproved && category == 'education') {
        if (approvedAssistanceAmount == null ||
            !approvedAssistanceAmount.isFinite ||
            approvedAssistanceAmount < 500 ||
            approvedAssistanceAmount > 1000) {
          throw StateError(
            'Education Incentive assistance must be from ₱500 to ₱1,000.',
          );
        }
        updates['assistanceAmount'] = approvedAssistanceAmount;
      }
      if (newStatus == statusApproved && category == 'bass') {
        if (approvedAssistanceAmount == null ||
            !approvedAssistanceAmount.isFinite ||
            approvedAssistanceAmount <= 0) {
          throw StateError('Enter a valid final BASS assistance amount.');
        }
        updates['assistanceAmount'] = approvedAssistanceAmount;
      }

      if (newStatus == statusApproved && _requiresBudgetReview(caseData)) {
        if (programRef == null || approvedAssistanceAmount == null) {
          throw StateError('The applicable quarterly budget was not found.');
        }
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The applicable quarterly budget was not found.');
        }
        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        if (allocated - utilized - reserved < approvedAssistanceAmount) {
          throw StateError(
            'The applicable budget does not have enough available balance.',
          );
        }
        final newReserved = reserved + approvedAssistanceAmount;
        final quarter = quarterForDate(effectiveDate);
        transaction.update(programRef, {
          'reserved': newReserved,
          'remaining': allocated - utilized - newReserved,
          'status': calculateBudgetHealth(
            allocated: allocated,
            utilized: utilized + newReserved,
            fiscalYear: effectiveDate.year,
            quarter: quarter,
            asOf: effectiveDate,
          ),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        updates.addAll({
          'budgetReservedProgramId': programRef.id,
          'budgetReservedAmount': approvedAssistanceAmount,
          'budgetReservedFiscalYear': effectiveDate.year,
          'budgetReservedQuarter': quarter,
          'budgetReservedAt': FieldValue.serverTimestamp(),
        });
      } else if (newStatus == statusReleased &&
          (caseData['budgetReservedAt'] != null ||
              _requiresBudgetDeduction(caseData, newStatus))) {
        if (programRef == null) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final amount =
            (caseData['budgetReservedAmount'] as num?)?.toDouble() ??
            budgetDeductionAmountForCase(caseData);
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        final hasReservation = caseData['budgetReservedAt'] != null;
        if (!hasReservation && allocated - utilized - reserved < amount) {
          throw StateError(
            'The applicable budget no longer has enough remaining balance '
            'for this case.',
          );
        }
        final newUtilized = utilized + amount;
        final newReserved = hasReservation
            ? (reserved - amount).clamp(0, double.infinity).toDouble()
            : reserved;
        final quarter =
            (caseData['budgetReservedQuarter'] as num?)?.toInt() ??
            quarterForDate(effectiveDate);
        final fiscalYear =
            (caseData['budgetReservedFiscalYear'] as num?)?.toInt() ??
            effectiveDate.year;
        final budgetStatus = calculateBudgetHealth(
          allocated: allocated,
          utilized: newUtilized + newReserved,
          fiscalYear: fiscalYear,
          quarter: quarter,
          asOf: effectiveDate,
        );

        transaction.update(programRef, {
          'utilized': newUtilized,
          'reserved': newReserved,
          'remaining': allocated - newUtilized - newReserved,
          'status': budgetStatus,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        transaction.set(budgetTransactionRef, {
          'programId': programRef.id,
          'caseId': caseId,
          'referenceNumber':
              referenceNumber ?? caseData['referenceNumber'] ?? '',
          'residentName': caseData['residentName'] ?? '',
          'serviceSubType': caseData['serviceSubType'] ?? '',
          'amount': amount,
          'type': 'deduction',
          'fiscalYear': fiscalYear,
          'quarter': quarter,
          'approvedBy': staffId,
          'releasedBy': staffId,
          'timestamp': FieldValue.serverTimestamp(),
        });

        updates.addAll({
          'budgetProgramId': programRef.id,
          'budgetDeductedAmount': amount,
          'budgetDeductedFiscalYear': fiscalYear,
          'budgetDeductedQuarter': quarter,
          'budgetDeductedAt': FieldValue.serverTimestamp(),
          'budgetReservedAt': FieldValue.delete(),
        });
      } else if (newStatus == statusRejected &&
          caseData['budgetReservedAt'] != null) {
        if (programRef == null) {
          throw StateError('The reserved budget program was not found.');
        }
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The reserved budget program was not found.');
        }
        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        final amount =
            (caseData['budgetReservedAmount'] as num?)?.toDouble() ?? 0;
        final newReserved = (reserved - amount)
            .clamp(0, double.infinity)
            .toDouble();
        final fiscalYear =
            (caseData['budgetReservedFiscalYear'] as num?)?.toInt() ??
            effectiveDate.year;
        final quarter =
            (caseData['budgetReservedQuarter'] as num?)?.toInt() ??
            quarterForDate(effectiveDate);
        transaction.update(programRef, {
          'reserved': newReserved,
          'remaining': allocated - utilized - newReserved,
          'status': calculateBudgetHealth(
            allocated: allocated,
            utilized: utilized + newReserved,
            fiscalYear: fiscalYear,
            quarter: quarter,
            asOf: effectiveDate,
          ),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        updates.addAll({
          'budgetReservedAt': FieldValue.delete(),
          'budgetReservedAmount': FieldValue.delete(),
          'budgetReservedProgramId': FieldValue.delete(),
        });
      }

      transaction.update(caseRef, updates);
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? caseData['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': staffId,
        'staffName': staffName,
        'action': 'Status changed: $previousStatus → $newStatus',
        'previousStatus': previousStatus,
        'newStatus': newStatus,
        'notes': notes,
        'smsSent': smsSent,
        'smsError': smsError,
        'smsBody': smsBody,
      });
    });
  }

  Future<void> requestForClaimingApproval({
    required String caseId,
    required String notes,
    required String staffId,
    required String staffName,
    required String staffRole,
    String? referenceNumber,
  }) async {
    if (staffRole == roleCaptain) {
      throw StateError('Captains should approve the case directly.');
    }
    if (staffRole != roleStaff && staffRole != roleOfficer) {
      throw StateError(
        'Only barangay staff or officers can submit this request.',
      );
    }

    final caseRef = _db.collection('cases').doc(caseId);
    final logRef = caseRef.collection('actionLog').doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(caseRef);
      if (!snapshot.exists) throw StateError('Case not found.');
      final data = snapshot.data()!;
      final status = normalizeCaseStatus((data['status'] ?? '').toString());
      if (status != statusApproved) {
        throw StateError(
          'Only Approved cases can be submitted for claiming approval.',
        );
      }
      if (data['claimingApprovalStatus'] == 'pending') {
        throw StateError('This case is already awaiting captain approval.');
      }

      transaction.update(caseRef, {
        'claimingApprovalStatus': 'pending',
        'claimingRequestedBy': staffId,
        'claimingRequestedByName': staffName,
        'claimingRequestedAt': FieldValue.serverTimestamp(),
        'claimingRequestReason': notes,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? data['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': staffId,
        'staffName': staffName,
        'action': 'For Claiming approval requested',
        'previousStatus': statusApproved,
        'newStatus': '',
        'notes': notes,
        'smsSent': false,
        'smsBody': '',
      });
    });
  }

  Future<void> rejectForClaimingApproval({
    required String caseId,
    required String reason,
    required String captainId,
    required String captainName,
    required String captainRole,
    String? referenceNumber,
  }) async {
    if (captainRole != roleCaptain) {
      throw StateError(
        'Only the Barangay Captain can reject a For Claiming request.',
      );
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Enter a reason for rejecting this request.');
    }
    final effectiveDate = DateTime.now();

    final caseRef = _db.collection('cases').doc(caseId);
    final initialCase = await caseRef.get();
    if (!initialCase.exists) throw StateError('Case not found.');
    final initialData = initialCase.data()!;
    final reservedProgramId = (initialData['budgetReservedProgramId'] ?? '')
        .toString();
    final programRef = reservedProgramId.isEmpty
        ? null
        : _db.collection('budgetPrograms').doc(reservedProgramId);
    final logRef = caseRef.collection('actionLog').doc();

    await _db.runTransaction((transaction) async {
      final caseSnapshot = await transaction.get(caseRef);
      if (!caseSnapshot.exists) throw StateError('Case not found.');
      final caseData = caseSnapshot.data()!;
      final currentStatus = normalizeCaseStatus(
        (caseData['status'] ?? '').toString(),
      );
      if (currentStatus != statusApproved ||
          caseData['claimingApprovalStatus'] != 'pending') {
        throw StateError(
          'This case is not awaiting Barangay Captain approval.',
        );
      }

      final updates = <String, dynamic>{
        'status': statusProcessing,
        'claimingApprovalStatus': 'rejected',
        'claimingRejectedBy': captainId,
        'claimingRejectedByName': captainName,
        'claimingRejectedAt': FieldValue.serverTimestamp(),
        'claimingRejectionReason': trimmedReason,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (caseData['budgetReservedAt'] != null && programRef != null) {
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The reserved budget program was not found.');
        }
        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        final amount =
            (caseData['budgetReservedAmount'] as num?)?.toDouble() ?? 0;
        final newReserved = (reserved - amount)
            .clamp(0, double.infinity)
            .toDouble();
        final fiscalYear =
            (caseData['budgetReservedFiscalYear'] as num?)?.toInt() ??
            effectiveDate.year;
        final quarter =
            (caseData['budgetReservedQuarter'] as num?)?.toInt() ??
            quarterForDate(effectiveDate);

        transaction.update(programRef, {
          'reserved': newReserved,
          'remaining': allocated - utilized - newReserved,
          'status': calculateBudgetHealth(
            allocated: allocated,
            utilized: utilized + newReserved,
            fiscalYear: fiscalYear,
            quarter: quarter,
            asOf: effectiveDate,
          ),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        updates.addAll({
          'budgetReservedAt': FieldValue.delete(),
          'budgetReservedAmount': FieldValue.delete(),
          'budgetReservedProgramId': FieldValue.delete(),
          'budgetReservedFiscalYear': FieldValue.delete(),
          'budgetReservedQuarter': FieldValue.delete(),
        });
      }

      transaction.update(caseRef, updates);
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? caseData['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': captainId,
        'staffName': captainName,
        'action': 'For Claiming approval rejected',
        'previousStatus': statusApproved,
        'newStatus': statusProcessing,
        'notes': trimmedReason,
        'smsSent': false,
        'smsBody': '',
      });
    });
  }

  Future<BudgetApprovalPreview> getBudgetApprovalPreview({
    required String caseId,
    DateTime? asOf,
    double? assistanceAmountOverride,
  }) async {
    final effectiveDate = asOf ?? DateTime.now();
    final caseSnapshot = await _db.collection('cases').doc(caseId).get();
    if (!caseSnapshot.exists) throw StateError('Case not found.');

    final caseData = caseSnapshot.data()!;
    final amount =
        assistanceAmountOverride ?? budgetDeductionAmountForCase(caseData);
    final programName = budgetProgramNameForCase(
      (caseData['serviceCategory'] ?? '').toString(),
      (caseData['serviceSubType'] ?? '').toString(),
    );
    if (amount <= 0 || programName == null) {
      return BudgetApprovalPreview(
        fiscalYear: effectiveDate.year,
        quarter: quarterForDate(effectiveDate),
        assistanceAmount: amount,
      );
    }

    final programRef = await _findQuarterlyProgram(programName, effectiveDate);
    if (programRef == null) {
      throw StateError(
        'No $programName allocation exists for '
        'FY ${effectiveDate.year} Q${quarterForDate(effectiveDate)}.',
      );
    }
    final programSnapshot = await programRef.get();
    final programData = programSnapshot.data()!;
    final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
    final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
    final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
    final remaining = allocated - utilized - reserved;

    return BudgetApprovalPreview(
      programId: programRef.id,
      programName: programName,
      fiscalYear: effectiveDate.year,
      quarter: quarterForDate(effectiveDate),
      allocated: allocated,
      utilized: utilized,
      reserved: reserved,
      currentRemaining: remaining,
      assistanceAmount: amount,
      projectedRemaining: remaining - amount,
      currentStatus: (programData['status'] ?? '').toString(),
    );
  }

  bool _requiresBudgetDeduction(
    Map<String, dynamic> caseData,
    String newStatus,
  ) {
    final amount = budgetDeductionAmountForCase(caseData);
    final programName = budgetProgramNameForCase(
      (caseData['serviceCategory'] ?? '').toString(),
      (caseData['serviceSubType'] ?? '').toString(),
    );
    return newStatus == 'released' &&
        amount > 0 &&
        programName != null &&
        caseData['budgetDeductedAt'] == null;
  }

  bool _requiresBudgetReview(Map<String, dynamic> caseData) {
    return budgetProgramNameForCase(
          (caseData['serviceCategory'] ?? '').toString(),
          (caseData['serviceSubType'] ?? '').toString(),
        ) !=
        null;
  }

  Future<DocumentReference<Map<String, dynamic>>?> _findQuarterlyProgram(
    String programName,
    DateTime date,
  ) async {
    final quarter = quarterForDate(date);
    final snapshot = await _db
        .collection('budgetPrograms')
        .where('name', isEqualTo: programName)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? latest;
    for (final doc in snapshot.docs) {
      final period = BudgetPeriod.fromData(doc.data());
      if (period.type != 'quarterly' ||
          period.fiscalYear != date.year ||
          period.quarter != quarter) {
        continue;
      }
      if (latest == null ||
          _lastUpdated(doc.data()) > _lastUpdated(latest.data()) ||
          (_lastUpdated(doc.data()) == _lastUpdated(latest.data()) &&
              doc.id.compareTo(latest.id) > 0)) {
        latest = doc;
      }
    }
    return latest?.reference;
  }

  int _lastUpdated(Map<String, dynamic> data) {
    return (data['lastUpdated'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
  }
}

class BudgetApprovalPreview {
  final String? programId;
  final String? programName;
  final int fiscalYear;
  final int quarter;
  final double allocated;
  final double utilized;
  final double reserved;
  final double currentRemaining;
  final double assistanceAmount;
  final double projectedRemaining;
  final String currentStatus;

  const BudgetApprovalPreview({
    this.programId,
    this.programName,
    required this.fiscalYear,
    required this.quarter,
    this.allocated = 0,
    this.utilized = 0,
    this.reserved = 0,
    this.currentRemaining = 0,
    this.assistanceAmount = 0,
    this.projectedRemaining = 0,
    this.currentStatus = '',
  });

  bool get hasBudgetImpact => programId != null && assistanceAmount > 0;
  bool get hasSufficientBalance => !hasBudgetImpact || projectedRemaining >= 0;
}

int quarterForDate(DateTime date) => ((date.month - 1) ~/ 3) + 1;

/// All budget-linked cases use the final assistance amount stored on the case.
double budgetDeductionAmountForCase(Map<String, dynamic> caseData) {
  return (caseData['assistanceAmount'] as num?)?.toDouble() ?? 0;
}

String? budgetProgramNameForCase(String category, String subType) {
  final normalizedCategory = category.trim().toLowerCase();
  final normalizedSubType = subType.trim().toLowerCase();

  if (normalizedCategory == 'bass') {
    if (normalizedSubType.contains('medical') ||
        normalizedSubType.contains('dialysis') ||
        normalizedSubType.contains('chemotherapy') ||
        normalizedSubType.contains('major operation')) {
      return 'BASS – Medical Assistance';
    }
    if (normalizedSubType.contains('burial')) {
      return 'BASS – Burial Assistance';
    }
    if (normalizedSubType.contains('drug') ||
        normalizedSubType.contains('rehabilitation')) {
      return 'BASS – Drug Rehabilitation';
    }
    if (normalizedSubType.contains('fire')) {
      return 'BASS – Fire Relief';
    }
  }
  if (normalizedCategory == 'education') return 'Education Incentive';
  return null;
}
