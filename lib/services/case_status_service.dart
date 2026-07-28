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

    if (_requiresBudgetDeduction(initialData, newStatus)) {
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

      if (_requiresBudgetDeduction(caseData, newStatus)) {
        if (programRef == null) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final amount = budgetDeductionAmountForCase(caseData);
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        if (allocated - utilized < amount) {
          throw StateError(
            'The applicable budget no longer has enough remaining balance '
            'for this case.',
          );
        }
        final newUtilized = utilized + amount;
        final quarter = quarterForDate(effectiveDate);
        final budgetStatus = calculateBudgetHealth(
          allocated: allocated,
          utilized: newUtilized,
          fiscalYear: effectiveDate.year,
          quarter: quarter,
          asOf: effectiveDate,
        );

        transaction.update(programRef, {
          'utilized': newUtilized,
          'remaining': allocated - newUtilized,
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
          'fiscalYear': effectiveDate.year,
          'quarter': quarter,
          'approvedBy': staffId,
          'releasedBy': staffId,
          'timestamp': FieldValue.serverTimestamp(),
        });

        updates.addAll({
          'budgetProgramId': programRef.id,
          'budgetDeductedAmount': amount,
          'budgetDeductedFiscalYear': effectiveDate.year,
          'budgetDeductedQuarter': quarter,
          'budgetDeductedAt': FieldValue.serverTimestamp(),
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
    final remaining = allocated - utilized;

    return BudgetApprovalPreview(
      programId: programRef.id,
      programName: programName,
      fiscalYear: effectiveDate.year,
      quarter: quarterForDate(effectiveDate),
      allocated: allocated,
      utilized: utilized,
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
