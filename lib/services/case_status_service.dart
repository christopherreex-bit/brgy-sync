import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/budget_health.dart';
import '../utils/budget_period.dart';

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
    String? referenceNumber,
    bool smsSent = false,
    String? smsError,
    String smsBody = '',
    DateTime? changedAt,
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
      final updates = <String, dynamic>{
        'status': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (_requiresBudgetDeduction(caseData, newStatus)) {
        if (programRef == null) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final amount = (caseData['assistanceAmount'] as num).toDouble();
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
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

  bool _requiresBudgetDeduction(
    Map<String, dynamic> caseData,
    String newStatus,
  ) {
    final amount = (caseData['assistanceAmount'] as num?)?.toDouble() ?? 0;
    return newStatus == 'released' &&
        amount > 0 &&
        caseData['budgetDeductedAt'] == null;
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

int quarterForDate(DateTime date) => ((date.month - 1) ~/ 3) + 1;

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
  if (normalizedCategory == 'beneficiary') {
    if (normalizedSubType.contains('senior')) {
      return 'Senior Citizen Birthday';
    }
    if (normalizedSubType.contains('pwd')) return 'PWD Birthday';
  }
  if (normalizedCategory == 'education') return 'Education Incentive';
  return null;
}
