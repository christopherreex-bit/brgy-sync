import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/case_model.dart';
import '../utils/budget_health.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Cases ────────────────────────────────────────────────────
  Future<String> createCase(CaseModel caseData) async {
    final year = DateTime.now().year;
    final counterRef = _db.collection('caseCounters').doc('$year');
    final docRef = _db.collection('cases').doc();
    final accountMobile =
        (caseData.requesterMobile.isNotEmpty
                ? caseData.requesterMobile
                : caseData.residentMobile)
            .replaceAll(RegExp(r'\D'), '');
    final registryQuery = await _db
        .collection('citizenRegistry')
        .where('mobile', isEqualTo: accountMobile)
        .limit(1)
        .get();
    final registryDocument = registryQuery.docs.firstOrNull;
    final registryData = registryDocument?.data();
    final registryVerified = registryData?['verificationStatus'] == 'verified';
    final registryName = _normalizeIdentity(registryData?['legalName']);
    final caseName = _normalizeIdentity(caseData.residentName);
    final identityMatches =
        caseData.requestedForSelf &&
        registryName.isNotEmpty &&
        registryName == caseName;
    final registryMatchStatus = registryDocument == null
        ? 'not_registered'
        : registryVerified && identityMatches
        ? 'verified_match'
        : 'needs_review';

    return _db.runTransaction((transaction) async {
      final counterSnapshot = await transaction.get(counterRef);
      final currentNumber = counterSnapshot.exists
          ? ((counterSnapshot.data()?['lastNumber'] as num?)?.toInt() ?? 0)
          : 0;
      final nextNumber = currentNumber + 1;
      final referenceNumber =
          'BRGY-$year-${nextNumber.toString().padLeft(5, '0')}';
      transaction.set(counterRef, {
        'lastNumber': nextNumber,
        'lastCaseId': docRef.id,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.set(docRef, {
        ...caseData.toMap(),
        'referenceNumber': referenceNumber,
        'sequenceYear': year,
        'sequenceNumber': nextNumber,
        'registryId': registryDocument?.id,
        'registryMatchStatus': registryMatchStatus,
        'registryCheckedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_db.collection('registryObservations').doc(docRef.id), {
        'caseId': docRef.id,
        'residentId': caseData.residentId,
        'residentName': caseData.residentName,
        'residentMobile': caseData.residentMobile,
        'residentAddress': caseData.residentAddress,
        if (caseData.addressLocation != null)
          'addressLocation': caseData.addressLocation,
        'source': caseData.submissionChannel,
        'observedAt': FieldValue.serverTimestamp(),
        'reviewStatus': 'pending',
      });

      return referenceNumber;
    });
  }

  static String _normalizeIdentity(Object? value) => (value ?? '')
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  Stream<QuerySnapshot> getCases({String? statusFilter}) {
    Query query = _db
        .collection('cases')
        .orderBy('submissionTimestamp', descending: true);
    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    return query.snapshots();
  }

  Future<DocumentSnapshot> getCase(String caseId) {
    return _db.collection('cases').doc(caseId).get();
  }

  /// Permanently deletes a case and its action logs while preserving an
  /// immutable deletion record for Audit Trail.
  Future<void> deleteCase(
    String caseId, {
    required String actorId,
    required String actorName,
    required String actorRole,
    required String source,
    required String deletionReason,
  }) async {
    final reason = deletionReason.trim();
    if (reason.isEmpty) {
      throw ArgumentError('A reason for deletion is required.');
    }

    final caseRef = _db.collection('cases').doc(caseId);
    final caseSnapshot = await caseRef.get();
    if (!caseSnapshot.exists) throw StateError('Case no longer exists.');

    final actionLog = caseRef.collection('actionLog');

    while (true) {
      final logSnapshot = await actionLog.limit(400).get();
      final isLastBatch = logSnapshot.docs.length < 400;
      if (!isLastBatch) {
        final batch = _db.batch();
        for (final log in logSnapshot.docs) {
          batch.delete(log.reference);
        }
        await batch.commit();
        continue;
      }

      await _db.runTransaction((transaction) async {
        final currentCase = await transaction.get(caseRef);
        if (!currentCase.exists) throw StateError('Case no longer exists.');

        final caseData = currentCase.data()!;
        final referenceNumber = (caseData['referenceNumber'] ?? '').toString();
        final auditRef = _db.collection('auditEvents').doc(caseId);
        final reversalRef = _db.collection('budgetReversals').doc(caseId);
        final budgetProgramId = (caseData['budgetProgramId'] ?? '').toString();
        final deductedAmount =
            (caseData['budgetDeductedAmount'] as num?)?.toDouble() ?? 0;
        final shouldReverseDeduction =
            caseData['budgetDeductedAt'] != null &&
            budgetProgramId.isNotEmpty &&
            deductedAmount > 0;
        final reservedProgramId = (caseData['budgetReservedProgramId'] ?? '')
            .toString();
        final reservedAmount =
            (caseData['budgetReservedAmount'] as num?)?.toDouble() ?? 0;
        final shouldReleaseReservation =
            caseData['budgetReservedAt'] != null &&
            reservedProgramId.isNotEmpty &&
            reservedAmount > 0;
        final shouldReverse =
            shouldReverseDeduction || shouldReleaseReservation;

        var restoredAmount = 0.0;
        if (shouldReverse) {
          final programRef = _db
              .collection('budgetPrograms')
              .doc(
                shouldReverseDeduction ? budgetProgramId : reservedProgramId,
              );
          final programSnapshot = await transaction.get(programRef);
          if (!programSnapshot.exists) {
            throw StateError(
              'Cannot delete this case because its linked budget no longer exists.',
            );
          }

          final programData = programSnapshot.data()!;
          final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
          final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
          final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
          restoredAmount = shouldReverseDeduction
              ? math.min(deductedAmount, utilized)
              : math.min(reservedAmount, reserved);
          final newUtilized = shouldReverseDeduction
              ? utilized - restoredAmount
              : utilized;
          final newReserved = shouldReleaseReservation
              ? reserved - restoredAmount
              : reserved;
          final fiscalYear =
              (caseData['budgetDeductedFiscalYear'] as num?)?.toInt() ??
              DateTime.now().year;
          final quarter =
              (caseData['budgetDeductedQuarter'] as num?)?.toInt() ?? 1;

          transaction.update(programRef, {
            'utilized': newUtilized,
            'reserved': newReserved,
            'remaining': allocated - newUtilized - newReserved,
            'status': calculateBudgetHealth(
              allocated: allocated,
              utilized: newUtilized + newReserved,
              fiscalYear: fiscalYear,
              quarter: quarter,
              asOf: DateTime.now(),
            ),
            'lastReversalCaseId': caseId,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          transaction.set(reversalRef, {
            'type': shouldReverseDeduction
                ? 'deduction_reversal'
                : 'reservation_release',
            'caseId': caseId,
            'referenceNumber': referenceNumber,
            'programId': shouldReverseDeduction
                ? budgetProgramId
                : reservedProgramId,
            'amount': restoredAmount,
            'originalDeductionAmount': deductedAmount,
            'originalReservedAmount': reservedAmount,
            'fiscalYear': fiscalYear,
            'quarter': quarter,
            'actorId': actorId,
            'actorName': actorName,
            'actorRole': actorRole,
            'reason': reason,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }

        transaction.set(auditRef, {
          'eventType': 'case_deleted',
          'action': shouldReverseDeduction
              ? 'Case deleted and budget deduction reversed'
              : shouldReleaseReservation
              ? 'Case deleted and reserved budget released'
              : 'Case deleted',
          'caseId': caseId,
          'referenceNumber': referenceNumber,
          'actorId': actorId,
          'staffName': actorName,
          'actorRole': actorRole,
          'source': source,
          'residentId': caseData['residentId'] ?? '',
          'residentName': caseData['residentName'] ?? '',
          'serviceCategory': caseData['serviceCategory'] ?? '',
          'serviceSubType': caseData['serviceSubType'] ?? '',
          'previousStatus': caseData['status'] ?? '',
          'deletionReason': reason,
          'notes': shouldReverse
              ? '$reason Budget reversal: '
                    '₱${restoredAmount.toStringAsFixed(2)} restored.'
              : reason,
          'budgetReversed': shouldReverse,
          if (shouldReverse) ...{
            'budgetProgramId': shouldReverseDeduction
                ? budgetProgramId
                : reservedProgramId,
            'budgetReversalAmount': restoredAmount,
            'budgetReversalId': caseId,
            'budgetDeductedFiscalYear': caseData['budgetDeductedFiscalYear'],
            'budgetDeductedQuarter': caseData['budgetDeductedQuarter'],
          },
          'smsSent': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
        for (final log in logSnapshot.docs) {
          transaction.delete(log.reference);
        }
        transaction.delete(caseRef);
      });
      break;
    }
  }

  Future<void> updateCaseStatus(
    String caseId,
    Map<String, dynamic> data,
  ) async {
    await _db.collection('cases').doc(caseId).update({
      ...data,
      'lastUpdated': FieldValue.serverTimestamp(),
      if (data.containsKey('status'))
        'statusUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addActionLog(String caseId, Map<String, dynamic> logData) async {
    await _db.collection('cases').doc(caseId).collection('actionLog').add({
      ...logData,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getActionLog(String caseId) {
    return _db
        .collection('cases')
        .doc(caseId)
        .collection('actionLog')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ─── Users ────────────────────────────────────────────────────
  Future<DocumentSnapshot> getUser(String uid) {
    return _db.collection('users').doc(uid).get();
  }

  // ─── SLA Config ───────────────────────────────────────────────
  Stream<QuerySnapshot> getSlaConfig() {
    return _db.collection('slaConfig').snapshots();
  }

  // ─── Budget Programs ──────────────────────────────────────────
  Stream<QuerySnapshot> getBudgetPrograms() {
    return _db.collection('budgetPrograms').snapshots();
  }

  // ─── Distributions ────────────────────────────────────────────
  Stream<QuerySnapshot> getDistributions({String? programType}) {
    Query query = _db.collection('distributions');
    if (programType != null) {
      query = query.where('programType', isEqualTo: programType);
    }
    return query.snapshots();
  }

  // ─── Reports ──────────────────────────────────────────────────
  Stream<QuerySnapshot> getReports() {
    return _db
        .collection('reports')
        .orderBy('generatedAt', descending: true)
        .snapshots();
  }
}
