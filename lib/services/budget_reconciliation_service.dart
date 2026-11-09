import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/budget_health.dart';
import '../utils/budget_period.dart';

/// Repairs budget totals after records were removed outside the normal
/// service-request deletion workflow (for example, direct test-data cleanup).
///
/// Budget programs remain the fast source used by approval and reporting, but
/// their utilized/reserved totals are rebuilt from the surviving source
/// records. Orphaned transaction rows are retained for audit purposes and
/// marked reversed instead of being silently deleted.
class BudgetReconciliationService {
  final FirebaseFirestore _db;

  BudgetReconciliationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<BudgetReconciliationResult> reconcile({DateTime? asOf}) async {
    final effectiveDate = asOf ?? DateTime.now();
    final results = await Future.wait([
      _db.collection('budgetPrograms').get(),
      _db.collection('cases').get(),
      _db.collection('distributions').get(),
      _db.collection('budgetTransactions').get(),
    ]);
    final programs = results[0];
    final cases = results[1];
    final distributions = results[2];
    final transactions = results[3];

    final existingCaseIds = cases.docs.map((doc) => doc.id).toSet();
    final utilizedByProgram = <String, double>{};
    final reservedByProgram = <String, double>{};
    final activeTransactionKeys = <String>{};

    // Prefer the immutable deduction ledger when it is linked to a service
    // request that still exists. This also supports older released requests
    // created before budget metadata was copied onto the request document.
    for (final doc in transactions.docs) {
      final data = doc.data();
      if (data['reversed'] == true) continue;
      final type = (data['type'] ?? '').toString();
      if (type != 'deduction' && type != 'distribution_deduction') continue;
      final caseId = (data['caseId'] ?? '').toString();
      final programId = (data['programId'] ?? '').toString();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      if (caseId.isEmpty ||
          !existingCaseIds.contains(caseId) ||
          programId.isEmpty ||
          amount <= 0) {
        continue;
      }
      utilizedByProgram.update(
        programId,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
      activeTransactionKeys.add('$caseId|$programId|$type');
    }

    for (final doc in cases.docs) {
      final data = doc.data();
      final deductedProgramId = (data['budgetProgramId'] ?? '').toString();
      final deductedAmount =
          (data['budgetDeductedAmount'] as num?)?.toDouble() ?? 0;
      if (data['budgetDeductedAt'] != null &&
          deductedProgramId.isNotEmpty &&
          deductedAmount > 0 &&
          !activeTransactionKeys.contains(
            '${doc.id}|$deductedProgramId|deduction',
          )) {
        utilizedByProgram.update(
          deductedProgramId,
          (value) => value + deductedAmount,
          ifAbsent: () => deductedAmount,
        );
      }

      final reservedProgramId = (data['budgetReservedProgramId'] ?? '')
          .toString();
      final reservedAmount =
          (data['budgetReservedAmount'] as num?)?.toDouble() ?? 0;
      if (data['budgetReservedAt'] != null &&
          reservedProgramId.isNotEmpty &&
          reservedAmount > 0) {
        reservedByProgram.update(
          reservedProgramId,
          (value) => value + reservedAmount,
          ifAbsent: () => reservedAmount,
        );
      }
    }

    for (final doc in distributions.docs) {
      final data = doc.data();
      final linkedCaseId =
          (data['beneficiaryRegistrationCaseId'] ?? data['caseId'] ?? '')
              .toString();
      final programId = (data['budgetProgramId'] ?? '').toString();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      if ((data['status'] ?? '').toString() == 'released' &&
          linkedCaseId.isNotEmpty &&
          existingCaseIds.contains(linkedCaseId) &&
          programId.isNotEmpty &&
          amount > 0 &&
          !activeTransactionKeys.contains(
            '$linkedCaseId|$programId|distribution_deduction',
          )) {
        utilizedByProgram.update(
          programId,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      }
    }

    final batch = _db.batch();
    var repairedPrograms = 0;
    var reversedTransactions = 0;

    for (final program in programs.docs) {
      final data = program.data();
      final allocated = (data['allocated'] as num?)?.toDouble() ?? 0;
      final storedUtilized = (data['utilized'] as num?)?.toDouble() ?? 0;
      final storedReserved = (data['reserved'] as num?)?.toDouble() ?? 0;
      final utilized = utilizedByProgram[program.id] ?? 0;
      final reserved = reservedByProgram[program.id] ?? 0;
      if ((storedUtilized - utilized).abs() < 0.005 &&
          (storedReserved - reserved).abs() < 0.005) {
        continue;
      }

      final period = BudgetPeriod.fromData(data);
      batch.update(program.reference, {
        'utilized': utilized,
        'reserved': reserved,
        'remaining': allocated - utilized - reserved,
        'status': calculateBudgetHealth(
          allocated: allocated,
          utilized: utilized + reserved,
          fiscalYear: period.fiscalYear ?? effectiveDate.year,
          quarter: period.quarter ?? 1,
          asOf: effectiveDate,
        ),
        'lastReconciledAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      repairedPrograms++;
    }

    for (final transaction in transactions.docs) {
      final data = transaction.data();
      if (data['reversed'] == true) continue;
      final type = (data['type'] ?? '').toString();
      if (type != 'deduction' && type != 'distribution_deduction') continue;
      final caseId = (data['caseId'] ?? '').toString();
      if (caseId.isEmpty || existingCaseIds.contains(caseId)) continue;

      batch.update(transaction.reference, {
        'reversed': true,
        'reversalReason':
            'Linked service request was deleted; removed from budget totals.',
        'reversedAt': FieldValue.serverTimestamp(),
      });
      reversedTransactions++;
    }

    if (repairedPrograms > 0 || reversedTransactions > 0) {
      await batch.commit();
    }
    return BudgetReconciliationResult(
      repairedPrograms: repairedPrograms,
      reversedTransactions: reversedTransactions,
    );
  }
}

class BudgetReconciliationResult {
  final int repairedPrograms;
  final int reversedTransactions;

  const BudgetReconciliationResult({
    required this.repairedPrograms,
    required this.reversedTransactions,
  });

  bool get changed => repairedPrograms > 0 || reversedTransactions > 0;
}
