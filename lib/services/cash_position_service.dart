import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../utils/budget_period.dart';

class CashPositionService {
  static const positionDocumentId = 'current';
  static const transferDelay = Duration(days: 1);

  final FirebaseFirestore _db;

  CashPositionService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _positionRef =>
      _db.collection('cashPositions').doc(positionDocumentId);

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPosition() =>
      _positionRef.snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMovements() => _db
      .collection('cashMovements')
      .orderBy('requestedAt', descending: true)
      .limit(100)
      .snapshots();

  Future<void> initialize({
    required double cashInBank,
    required double cashOnHand,
    required String reason,
    required UserModel actor,
    bool excessAcknowledged = false,
  }) async {
    if (!actor.isCaptain && !actor.isTreasurer) {
      throw StateError(
        'Only the Barangay Captain or Treasurer can initialize cash balances.',
      );
    }
    if (!cashInBank.isFinite ||
        cashInBank < 0 ||
        !cashOnHand.isFinite ||
        cashOnHand < 0) {
      throw StateError('Opening balances must be valid non-negative amounts.');
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Enter the basis for the opening balances.');
    }
    final budget = await getCurrentBudgetPosition();
    final totalLiquidCash = cashInBank + cashOnHand;
    final difference = totalLiquidCash - budget.undisbursed;
    final onHandCoverageDifference = cashOnHand - budget.reserved;
    final exceedsUndisbursedBudget = difference > 0;
    if (exceedsUndisbursedBudget && !excessAcknowledged) {
      throw StateError(
        'Cash exceeds the fiscal year undisbursed program budget. Confirm the '
        'difference and provide a reconciliation explanation.',
      );
    }

    final movementRef = _db.collection('cashMovements').doc();
    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(_positionRef);
      if (existing.exists && existing.data()?['initialized'] == true) {
        throw StateError('The cash position has already been initialized.');
      }
      transaction.set(_positionRef, {
        'initialized': true,
        'cashInBank': cashInBank,
        'cashOnHand': cashOnHand,
        'cashInTransit': 0.0,
        'budgetFiscalYearAtInitialization': budget.fiscalYear,
        'budgetAllocatedAtInitialization': budget.allocated,
        'budgetUtilizedAtInitialization': budget.utilized,
        'budgetReservedAtInitialization': budget.reserved,
        'budgetAvailableAtInitialization': budget.available,
        'budgetUndisbursedAtInitialization': budget.undisbursed,
        'liquidCashAtInitialization': totalLiquidCash,
        'cashToBudgetDifferenceAtInitialization': difference,
        'onHandToReservedDifferenceAtInitialization': onHandCoverageDifference,
        'cashExceededUndisbursedBudget': exceedsUndisbursedBudget,
        'cashBudgetDifferenceAcknowledged': excessAcknowledged,
        'reconciliationReason': trimmedReason,
        'initializedAt': FieldValue.serverTimestamp(),
        'initializedBy': actor.uid,
        'initializedByName': actor.name,
        'lastMovementId': movementRef.id,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(movementRef, {
        'type': 'opening_balance',
        'status': 'completed',
        'bankAmount': cashInBank,
        'onHandAmount': cashOnHand,
        'budgetFiscalYear': budget.fiscalYear,
        'budgetAllocated': budget.allocated,
        'budgetUtilized': budget.utilized,
        'budgetReserved': budget.reserved,
        'budgetAvailable': budget.available,
        'budgetUndisbursed': budget.undisbursed,
        'liquidCash': totalLiquidCash,
        'cashToBudgetDifference': difference,
        'onHandToReservedDifference': onHandCoverageDifference,
        'cashExceededUndisbursedBudget': exceedsUndisbursedBudget,
        'cashBudgetDifferenceAcknowledged': excessAcknowledged,
        'reason': trimmedReason,
        'requestedAt': FieldValue.serverTimestamp(),
        'effectiveAt': FieldValue.serverTimestamp(),
        'requestedBy': actor.uid,
        'requestedByName': actor.name,
        'requestedByRole': actor.role,
      });
    });
  }

  Future<CashBudgetPosition> getCurrentBudgetPosition({DateTime? asOf}) async {
    final date = asOf ?? DateTime.now();
    final fiscalYear = date.year;
    final snapshot = await _db.collection('budgetPrograms').get();
    final latestByProgramAndQuarter =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    for (final document in snapshot.docs) {
      final data = document.data();
      final period = BudgetPeriod.fromData(data);
      if (period.type != 'quarterly' ||
          period.fiscalYear != fiscalYear ||
          period.quarter == null) {
        continue;
      }
      final name = (data['name'] ?? '').toString().trim().toLowerCase();
      if (name.isEmpty) continue;
      final key = '$name|q${period.quarter}';
      final existing = latestByProgramAndQuarter[key];
      final updated =
          (data['lastUpdated'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final existingUpdated = existing == null
          ? -1
          : (existing.data()['lastUpdated'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
      if (existing == null ||
          updated > existingUpdated ||
          (updated == existingUpdated &&
              document.id.compareTo(existing.id) > 0)) {
        latestByProgramAndQuarter[key] = document;
      }
    }

    var allocated = 0.0;
    var utilized = 0.0;
    var reserved = 0.0;
    for (final document in latestByProgramAndQuarter.values) {
      final data = document.data();
      allocated += (data['allocated'] as num?)?.toDouble() ?? 0;
      utilized += (data['utilized'] as num?)?.toDouble() ?? 0;
      reserved += (data['reserved'] as num?)?.toDouble() ?? 0;
    }
    return CashBudgetPosition(
      fiscalYear: fiscalYear,
      allocated: allocated,
      utilized: utilized,
      reserved: reserved,
      available: allocated - utilized - reserved,
      undisbursed: allocated - utilized,
    );
  }

  Future<void> requestBankToHandTransfer({
    required double amount,
    required String reason,
    required UserModel actor,
    DateTime? requestedAt,
  }) async {
    if (!actor.isCaptain && !actor.isTreasurer) {
      throw StateError(
        'Only the Barangay Captain or Treasurer can request a bank withdrawal.',
      );
    }
    if (!amount.isFinite || amount <= 0) {
      throw StateError('Enter a valid amount greater than zero.');
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Enter the reason for the bank withdrawal.');
    }
    final requestTime = requestedAt ?? DateTime.now();
    final effectiveAt = requestTime.add(transferDelay);
    final movementRef = _db.collection('cashMovements').doc();

    await _db.runTransaction((transaction) async {
      final position = await transaction.get(_positionRef);
      if (!position.exists || position.data()?['initialized'] != true) {
        throw StateError(
          'Initialize the cash position before transferring funds.',
        );
      }
      final data = position.data()!;
      final bank = (data['cashInBank'] as num?)?.toDouble() ?? 0;
      final transit = (data['cashInTransit'] as num?)?.toDouble() ?? 0;
      if (bank < amount) {
        throw StateError('Cash in bank is insufficient for this transfer.');
      }

      transaction.update(_positionRef, {
        'cashInBank': bank - amount,
        'cashInTransit': transit + amount,
        'lastMovementId': movementRef.id,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(movementRef, {
        'type': 'bank_to_hand',
        'status': 'pending',
        'amount': amount,
        'reason': trimmedReason,
        'requestedAt': Timestamp.fromDate(requestTime),
        'effectiveAt': Timestamp.fromDate(effectiveAt),
        'requestedBy': actor.uid,
        'requestedByName': actor.name,
        'requestedByRole': actor.role,
      });
    });
  }

  Future<void> recordBankReceipt({
    required double amount,
    required String source,
    required String referenceNumber,
    required String reason,
    required UserModel actor,
  }) async {
    if (!actor.isCaptain && !actor.isTreasurer) {
      throw StateError(
        'Only the Barangay Captain or Treasurer can record incoming funds.',
      );
    }
    if (!amount.isFinite || amount <= 0) {
      throw StateError('Enter a valid amount greater than zero.');
    }
    final trimmedSource = source.trim();
    final trimmedReference = referenceNumber.trim();
    final trimmedReason = reason.trim();
    if (trimmedSource.isEmpty ||
        trimmedReference.isEmpty ||
        trimmedReason.isEmpty) {
      throw StateError(
        'Enter the funding source, deposit/reference number, and reason.',
      );
    }
    final movementRef = _db.collection('cashMovements').doc();
    await _db.runTransaction((transaction) async {
      final position = await transaction.get(_positionRef);
      if (!position.exists || position.data()?['initialized'] != true) {
        throw StateError(
          'Initialize the cash position before recording incoming funds.',
        );
      }
      final data = position.data()!;
      final bank = (data['cashInBank'] as num?)?.toDouble() ?? 0;
      transaction.update(_positionRef, {
        'cashInBank': bank + amount,
        'lastMovementId': movementRef.id,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(movementRef, {
        'type': 'bank_receipt',
        'status': 'completed',
        'amount': amount,
        'source': trimmedSource,
        'referenceNumber': trimmedReference,
        'reason': trimmedReason,
        'requestedAt': FieldValue.serverTimestamp(),
        'effectiveAt': FieldValue.serverTimestamp(),
        'requestedBy': actor.uid,
        'requestedByName': actor.name,
        'requestedByRole': actor.role,
      });
    });
  }

  Future<void> reconcileMaturedTransfers({DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final pending = await _db
        .collection('cashMovements')
        .where('status', isEqualTo: 'pending')
        .get();

    for (final movement in pending.docs) {
      final movementData = movement.data();
      final effectiveAt = movementData['effectiveAt'];
      if (movementData['type'] != 'bank_to_hand' ||
          effectiveAt is! Timestamp ||
          effectiveAt.toDate().isAfter(now)) {
        continue;
      }
      await _db.runTransaction((transaction) async {
        final currentMovement = await transaction.get(movement.reference);
        final position = await transaction.get(_positionRef);
        if (!currentMovement.exists ||
            currentMovement.data()?['status'] != 'pending' ||
            !position.exists) {
          return;
        }
        final amount =
            (currentMovement.data()?['amount'] as num?)?.toDouble() ?? 0;
        final data = position.data()!;
        final hand = (data['cashOnHand'] as num?)?.toDouble() ?? 0;
        final transit = (data['cashInTransit'] as num?)?.toDouble() ?? 0;
        transaction.update(_positionRef, {
          'cashOnHand': hand + amount,
          'cashInTransit': (transit - amount)
              .clamp(0, double.infinity)
              .toDouble(),
          'lastMovementId': movement.id,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        transaction.update(movement.reference, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });
      });
    }
  }
}

class CashBudgetPosition {
  final int fiscalYear;
  final double allocated;
  final double utilized;
  final double reserved;
  final double available;
  final double undisbursed;

  const CashBudgetPosition({
    required this.fiscalYear,
    required this.allocated,
    required this.utilized,
    required this.reserved,
    required this.available,
    required this.undisbursed,
  });
}
