import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../utils/budget_period.dart';
import '../utils/philippine_business_calendar.dart';
import 'financial_evidence_service.dart';
import 'financial_slip_ocr_service.dart';

class CashPositionService {
  static const positionDocumentId = 'current';
  static const lowCashThresholdPercent = 20.0;

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
        'requestedByRole': actor.effectiveRole,
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

  Future<CashBudgetPosition> getCurrentQuarterBudgetPosition({
    DateTime? asOf,
  }) async {
    final date = asOf ?? DateTime.now();
    final fiscalYear = date.year;
    final quarter = ((date.month - 1) ~/ 3) + 1;
    final snapshot = await _db.collection('budgetPrograms').get();
    final latestByProgram =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    for (final document in snapshot.docs) {
      final data = document.data();
      final period = BudgetPeriod.fromData(data);
      if (period.type != 'quarterly' ||
          period.fiscalYear != fiscalYear ||
          period.quarter != quarter) {
        continue;
      }
      final name = (data['name'] ?? '').toString().trim().toLowerCase();
      if (name.isEmpty) continue;
      final existing = latestByProgram[name];
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
        latestByProgram[name] = document;
      }
    }

    var allocated = 0.0;
    var utilized = 0.0;
    var reserved = 0.0;
    for (final document in latestByProgram.values) {
      final data = document.data();
      allocated += (data['allocated'] as num?)?.toDouble() ?? 0;
      utilized += (data['utilized'] as num?)?.toDouble() ?? 0;
      reserved += (data['reserved'] as num?)?.toDouble() ?? 0;
    }
    return CashBudgetPosition(
      fiscalYear: fiscalYear,
      quarter: quarter,
      allocated: allocated,
      utilized: utilized,
      reserved: reserved,
      available: allocated - utilized - reserved,
      undisbursed: allocated - utilized,
    );
  }

  static CashLiquidityAssessment assessLiquidity({
    required double cashInBank,
    required double cashOnHand,
    required double cashInTransit,
    required double reserved,
    required double undisbursedBudget,
    double thresholdPercent = lowCashThresholdPercent,
  }) {
    final thresholdFromBudget =
        math.max(0.0, undisbursedBudget) * thresholdPercent / 100;
    final targetCashOnHand = math.max(reserved, thresholdFromBudget).toDouble();
    final incomingLiquidity = cashOnHand + cashInTransit;
    final shortage = math.max(0.0, targetCashOnHand - incomingLiquidity);
    return CashLiquidityAssessment(
      needsBankTransfer: shortage > 0.005 && cashInBank > 0,
      targetCashOnHand: targetCashOnHand,
      availableOrIncomingCash: incomingLiquidity,
      suggestedTransfer: math
          .min(shortage, math.max(0.0, cashInBank))
          .toDouble(),
      thresholdPercent: thresholdPercent,
    );
  }

  /// Creates at most one low-cash alert per day for the current fiscal
  /// quarter. The deterministic document ID prevents duplicate alerts when
  /// several screens or workflows run the same check concurrently.
  Future<void> notifyTreasurerIfCashIsLow({DateTime? asOf}) async {
    final date = asOf ?? DateTime.now();
    final position = await _positionRef.get();
    final cash = position.data();
    if (!position.exists || cash?['initialized'] != true) return;

    final budget = await getCurrentQuarterBudgetPosition(asOf: date);
    if (budget.allocated <= 0) return;
    final assessment = assessLiquidity(
      cashInBank: (cash?['cashInBank'] as num?)?.toDouble() ?? 0,
      cashOnHand: (cash?['cashOnHand'] as num?)?.toDouble() ?? 0,
      cashInTransit: (cash?['cashInTransit'] as num?)?.toDouble() ?? 0,
      reserved: budget.reserved,
      undisbursedBudget: budget.undisbursed,
    );
    if (!assessment.needsBankTransfer) return;

    final dayKey =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final notificationRef = _db
        .collection('notifications')
        .doc('cash_liquidity_${date.year}_q${budget.quarter}_$dayKey');
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _db.runTransaction((transaction) async {
      if ((await transaction.get(notificationRef)).exists) return;
      transaction.set(notificationRef, {
        'type': 'cash_transfer_recommended',
        'title': 'Cash-on-hand transfer recommended',
        'message':
            'Current and incoming cash is ${_peso(assessment.availableOrIncomingCash)}, below the ${_peso(assessment.targetCashOnHand)} liquidity target for FY ${budget.fiscalYear} Q${budget.quarter}. Consider transferring ${_peso(assessment.suggestedTransfer)} from the bank.',
        'caseId': '',
        'referenceNumber': '',
        'recipientId': '',
        'audienceRoles': const ['treasurer'],
        'createdById': currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String>[],
        'deletedBy': <String>[],
        'fiscalYear': budget.fiscalYear,
        'quarter': budget.quarter,
        'thresholdPercent': assessment.thresholdPercent,
        'targetCashOnHand': assessment.targetCashOnHand,
        'availableOrIncomingCash': assessment.availableOrIncomingCash,
        'suggestedTransfer': assessment.suggestedTransfer,
      });
    });
  }

  static String _peso(double value) => '₱${value.toStringAsFixed(2)}';

  Future<void> requestBankToHandTransfer({
    required double amount,
    required String referenceNumber,
    required String transactionDate,
    required String financialInstitution,
    required String reason,
    required UserModel actor,
    required FinancialEvidenceDraft evidence,
    required bool ocrConfirmed,
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
    final trimmedReference = referenceNumber.trim();
    final trimmedDate = transactionDate.trim();
    final trimmedInstitution = financialInstitution.trim();
    if (trimmedReason.isEmpty ||
        trimmedReference.isEmpty ||
        trimmedDate.isEmpty ||
        trimmedInstitution.isEmpty) {
      throw StateError('Complete all withdrawal-slip and accounting details.');
    }
    if (!ocrConfirmed) throw StateError('Review and confirm the slip details.');
    final requestTime = requestedAt ?? DateTime.now();
    final schedule = PhilippineBusinessCalendar.bankToCashSchedule(requestTime);
    final movementRef = _db.collection('cashMovements').doc();
    final evidenceService = FinancialEvidenceService();
    final evidenceData = await evidenceService.upload(
      ownerId: actor.uid,
      movementId: movementRef.id,
      draft: evidence,
    );

    try {
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
          'referenceNumber': trimmedReference,
          'slipTransactionDate': trimmedDate,
          'financialInstitution': trimmedInstitution,
          'reason': trimmedReason,
          'requestedAt': Timestamp.fromDate(requestTime),
          'transitStartsAt': Timestamp.fromDate(schedule.startsAt),
          'effectiveAt': Timestamp.fromDate(schedule.arrivesAt),
          'requestedBy': actor.uid,
          'requestedByName': actor.name,
          'requestedByRole': actor.effectiveRole,
          'evidence': evidenceData,
          'ocrExtraction': evidence.ocrResult?.toMap(),
          'ocrConfirmed': true,
        });
      });
    } catch (_) {
      try {
        await evidenceService.delete(evidenceData['databasePath'].toString());
      } catch (_) {
        // Preserve the original ledger error; orphan cleanup is best effort.
      }
      rethrow;
    }
  }

  Future<void> recordBankReceipt({
    required double amount,
    required String source,
    required String referenceNumber,
    required String transactionDate,
    required String financialInstitution,
    required String reason,
    required UserModel actor,
    required FinancialEvidenceDraft evidence,
    required bool ocrConfirmed,
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
    final trimmedDate = transactionDate.trim();
    final trimmedInstitution = financialInstitution.trim();
    final trimmedReason = reason.trim();
    if (trimmedSource.isEmpty ||
        trimmedReference.isEmpty ||
        trimmedDate.isEmpty ||
        trimmedInstitution.isEmpty ||
        trimmedReason.isEmpty) {
      throw StateError(
        'Complete all deposit-slip, funding-source, and accounting details.',
      );
    }
    if (!ocrConfirmed) throw StateError('Review and confirm the slip details.');
    final movementRef = _db.collection('cashMovements').doc();
    final evidenceService = FinancialEvidenceService();
    final evidenceData = await evidenceService.upload(
      ownerId: actor.uid,
      movementId: movementRef.id,
      draft: evidence,
    );
    try {
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
          'slipTransactionDate': trimmedDate,
          'financialInstitution': trimmedInstitution,
          'reason': trimmedReason,
          'requestedAt': FieldValue.serverTimestamp(),
          'effectiveAt': FieldValue.serverTimestamp(),
          'requestedBy': actor.uid,
          'requestedByName': actor.name,
          'requestedByRole': actor.effectiveRole,
          'evidence': evidenceData,
          'ocrExtraction': evidence.ocrResult?.toMap(),
          'ocrConfirmed': true,
        });
      });
    } catch (_) {
      try {
        await evidenceService.delete(evidenceData['databasePath'].toString());
      } catch (_) {
        // Preserve the original ledger error; orphan cleanup is best effort.
      }
      rethrow;
    }
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
    await notifyTreasurerIfCashIsLow(asOf: now);
  }
}

class CashBudgetPosition {
  final int fiscalYear;
  final int? quarter;
  final double allocated;
  final double utilized;
  final double reserved;
  final double available;
  final double undisbursed;

  const CashBudgetPosition({
    required this.fiscalYear,
    this.quarter,
    required this.allocated,
    required this.utilized,
    required this.reserved,
    required this.available,
    required this.undisbursed,
  });
}

class CashLiquidityAssessment {
  final bool needsBankTransfer;
  final double targetCashOnHand;
  final double availableOrIncomingCash;
  final double suggestedTransfer;
  final double thresholdPercent;

  const CashLiquidityAssessment({
    required this.needsBankTransfer,
    required this.targetCashOnHand,
    required this.availableOrIncomingCash,
    required this.suggestedTransfer,
    required this.thresholdPercent,
  });
}
