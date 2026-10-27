import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../utils/budget_health.dart';
import '../utils/budget_period.dart';
import 'cash_position_service.dart';

class IncentiveDistributionService {
  static const double fixedIncentiveAmount = 1000;
  final FirebaseFirestore _db;

  IncentiveDistributionService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchDistributions() => _db
      .collection('distributions')
      .orderBy('releasedAt', descending: true)
      .limit(100)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchBeneficiaryRegistrations() =>
      _db
          .collection('cases')
          .where('serviceCategory', isEqualTo: 'beneficiary')
          .snapshots();

  Future<void> release({
    required String registrationCaseId,
    required String programType,
    required String reason,
    required UserModel actor,
    DateTime? releasedAt,
  }) async {
    if (!actor.isCaptain) {
      throw StateError(
        'Only the Barangay Captain can authorize an incentive release.',
      );
    }
    const amount = fixedIncentiveAmount;
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Enter the reason or authority for this distribution.');
    }
    final programName = switch (programType) {
      'senior_birthday' => 'Senior Citizen Birthday',
      'pwd_birthday' => 'PWD Birthday',
      _ => throw StateError('Select a valid incentive program.'),
    };
    final expectedSubType = switch (programType) {
      'senior_birthday' => 'Senior Citizen Birthday Program',
      _ => 'PWD Birthday Program',
    };
    final date = releasedAt ?? DateTime.now();
    await CashPositionService(
      firestore: _db,
    ).reconcileMaturedTransfers(asOf: date);

    final caseRef = _db.collection('cases').doc(registrationCaseId);
    final programRef = await _findQuarterlyProgram(programName, date);
    if (programRef == null) {
      throw StateError(
        'No $programName allocation exists for FY ${date.year} Q${_quarter(date)}.',
      );
    }
    final distributionId = '${registrationCaseId}_${date.year}_$programType';
    final distributionRef = _db.collection('distributions').doc(distributionId);
    final budgetTransactionRef = _db
        .collection('budgetTransactions')
        .doc('distribution_$distributionId');
    final cashPositionRef = _db
        .collection('cashPositions')
        .doc(CashPositionService.positionDocumentId);
    final cashMovementRef = _db
        .collection('cashMovements')
        .doc('distribution_$distributionId');

    await _db.runTransaction((transaction) async {
      final registration = await transaction.get(caseRef);
      final program = await transaction.get(programRef);
      final cashPosition = await transaction.get(cashPositionRef);
      final existingDistribution = await transaction.get(distributionRef);

      if (!registration.exists) {
        throw StateError('The beneficiary registration could not be found.');
      }
      final caseData = registration.data()!;
      if ((caseData['serviceCategory'] ?? '').toString() != 'beneficiary' ||
          (caseData['serviceSubType'] ?? '').toString() != expectedSubType ||
          (caseData['status'] ?? '').toString() != 'released') {
        throw StateError(
          'Only a completed $expectedSubType registration can receive this incentive.',
        );
      }
      if (existingDistribution.exists) {
        throw StateError(
          'This beneficiary already has a $programName distribution for FY ${date.year}.',
        );
      }
      if (!program.exists) {
        throw StateError('The applicable quarterly allocation was not found.');
      }
      if (!cashPosition.exists || cashPosition.data()?['initialized'] != true) {
        throw StateError(
          'Initialize Cash Position before releasing an incentive.',
        );
      }

      final programData = program.data()!;
      final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
      final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
      final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
      if (allocated - utilized - reserved < amount) {
        throw StateError(
          'The $programName budget does not have enough available balance.',
        );
      }
      final cashData = cashPosition.data()!;
      final cashOnHand = (cashData['cashOnHand'] as num?)?.toDouble() ?? 0;
      if (cashOnHand < amount) {
        throw StateError(
          'Cash on hand is insufficient. Transfer funds from the bank and '
          'wait for them to arrive before releasing this incentive.',
        );
      }

      final newUtilized = utilized + amount;
      final quarter = _quarter(date);
      transaction.update(programRef, {
        'utilized': newUtilized,
        'remaining': allocated - newUtilized - reserved,
        'status': calculateBudgetHealth(
          allocated: allocated,
          utilized: newUtilized + reserved,
          fiscalYear: date.year,
          quarter: quarter,
          asOf: date,
        ),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.update(cashPositionRef, {
        'cashOnHand': cashOnHand - amount,
        'lastMovementId': cashMovementRef.id,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(distributionRef, {
        'programType': programType,
        'programName': programName,
        'beneficiaryRegistrationCaseId': registrationCaseId,
        'referenceNumber': caseData['referenceNumber'] ?? '',
        'beneficiaryName':
            caseData['fullName'] ?? caseData['residentName'] ?? '',
        'residentId': caseData['residentId'] ?? '',
        'amount': amount,
        'reason': trimmedReason,
        'status': 'released',
        'fiscalYear': date.year,
        'quarter': quarter,
        'budgetProgramId': programRef.id,
        'releasedAt': FieldValue.serverTimestamp(),
        'releasedBy': actor.uid,
        'releasedByName': actor.name,
        'releasedByRole': actor.role,
      });
      transaction.set(budgetTransactionRef, {
        'programId': programRef.id,
        'distributionId': distributionId,
        'caseId': registrationCaseId,
        'referenceNumber': caseData['referenceNumber'] ?? '',
        'residentName': caseData['fullName'] ?? caseData['residentName'] ?? '',
        'serviceSubType': expectedSubType,
        'amount': amount,
        'type': 'distribution_deduction',
        'fiscalYear': date.year,
        'quarter': quarter,
        'releasedBy': actor.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      transaction.set(cashMovementRef, {
        'type': 'case_disbursement',
        'status': 'completed',
        'amount': amount,
        'reason': trimmedReason,
        'caseId': registrationCaseId,
        'distributionId': distributionId,
        'referenceNumber': caseData['referenceNumber'] ?? '',
        'residentName': caseData['fullName'] ?? caseData['residentName'] ?? '',
        'serviceSubType': expectedSubType,
        'requestedAt': FieldValue.serverTimestamp(),
        'effectiveAt': FieldValue.serverTimestamp(),
        'requestedBy': actor.uid,
        'requestedByName': actor.name,
        'requestedByRole': actor.role,
      });
    });
  }

  Future<IncentiveReleasePreview> getReleasePreview({
    required String programType,
    DateTime? asOf,
  }) async {
    final date = asOf ?? DateTime.now();
    final programName = switch (programType) {
      'senior_birthday' => 'Senior Citizen Birthday',
      'pwd_birthday' => 'PWD Birthday',
      _ => throw StateError('Select a valid incentive program.'),
    };
    final programRef = await _findQuarterlyProgram(programName, date);
    if (programRef == null) {
      throw StateError(
        'No $programName allocation exists for FY ${date.year} Q${_quarter(date)}.',
      );
    }
    final results = await Future.wait([
      programRef.get(),
      _db
          .collection('cashPositions')
          .doc(CashPositionService.positionDocumentId)
          .get(),
    ]);
    final program = results[0].data() ?? const <String, dynamic>{};
    final cash = results[1].data() ?? const <String, dynamic>{};
    final allocated = (program['allocated'] as num?)?.toDouble() ?? 0;
    final utilized = (program['utilized'] as num?)?.toDouble() ?? 0;
    final reserved = (program['reserved'] as num?)?.toDouble() ?? 0;
    final available = allocated - utilized - reserved;
    final cashOnHand = (cash['cashOnHand'] as num?)?.toDouble() ?? 0;
    return IncentiveReleasePreview(
      programName: programName,
      fiscalYear: date.year,
      quarter: _quarter(date),
      allocated: allocated,
      utilized: utilized,
      reserved: reserved,
      available: available,
      amount: fixedIncentiveAmount,
      remainingAfterRelease: available - fixedIncentiveAmount,
      cashOnHand: cashOnHand,
      cashOnHandAfterRelease: cashOnHand - fixedIncentiveAmount,
      cashPositionInitialized: cash['initialized'] == true,
    );
  }

  Future<DocumentReference<Map<String, dynamic>>?> _findQuarterlyProgram(
    String programName,
    DateTime date,
  ) async {
    final snapshot = await _db
        .collection('budgetPrograms')
        .where('name', isEqualTo: programName)
        .get();
    QueryDocumentSnapshot<Map<String, dynamic>>? latest;
    for (final document in snapshot.docs) {
      final period = BudgetPeriod.fromData(document.data());
      if (period.type != 'quarterly' ||
          period.fiscalYear != date.year ||
          period.quarter != _quarter(date)) {
        continue;
      }
      final updated =
          (document.data()['lastUpdated'] as Timestamp?)
              ?.millisecondsSinceEpoch ??
          0;
      final latestUpdated = latest == null
          ? -1
          : (latest.data()['lastUpdated'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
      if (latest == null ||
          updated > latestUpdated ||
          (updated == latestUpdated && document.id.compareTo(latest.id) > 0)) {
        latest = document;
      }
    }
    return latest?.reference;
  }

  int _quarter(DateTime date) => ((date.month - 1) ~/ 3) + 1;
}

class IncentiveReleasePreview {
  final String programName;
  final int fiscalYear;
  final int quarter;
  final double allocated;
  final double utilized;
  final double reserved;
  final double available;
  final double amount;
  final double remainingAfterRelease;
  final double cashOnHand;
  final double cashOnHandAfterRelease;
  final bool cashPositionInitialized;

  const IncentiveReleasePreview({
    required this.programName,
    required this.fiscalYear,
    required this.quarter,
    required this.allocated,
    required this.utilized,
    required this.reserved,
    required this.available,
    required this.amount,
    required this.remainingAfterRelease,
    required this.cashOnHand,
    required this.cashOnHandAfterRelease,
    required this.cashPositionInitialized,
  });

  bool get hasEnoughBudget => available >= amount;
  bool get hasEnoughCash => cashPositionInitialized && cashOnHand >= amount;
  bool get canRelease => hasEnoughBudget && hasEnoughCash;
}
