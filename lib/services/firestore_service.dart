import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/case_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Cases ────────────────────────────────────────────────────
  Future<String> createCase(CaseModel caseData) async {
    final year = DateTime.now().year;
    final counterRef = _db.collection('caseCounters').doc('$year');
    final docRef = _db.collection('cases').doc();

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
      });

      return referenceNumber;
    });
  }

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
  }) async {
    final caseRef = _db.collection('cases').doc(caseId);
    final caseSnapshot = await caseRef.get();
    if (!caseSnapshot.exists) throw StateError('Case no longer exists.');

    final caseData = caseSnapshot.data() as Map<String, dynamic>;
    final referenceNumber = (caseData['referenceNumber'] ?? '').toString();
    final actionLog = caseRef.collection('actionLog');

    while (true) {
      final logSnapshot = await actionLog.limit(400).get();
      final batch = _db.batch();
      for (final log in logSnapshot.docs) {
        batch.delete(log.reference);
      }

      final isLastBatch = logSnapshot.docs.length < 400;
      if (isLastBatch) {
        batch.set(_db.collection('auditEvents').doc(caseId), {
          'eventType': 'case_deleted',
          'action': 'Case deleted',
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
          'notes': actorRole == 'resident'
              ? 'Permanently deleted by the resident from My Cases.'
              : 'Permanently deleted by the Barangay Captain from Case Queue.',
          'smsSent': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
        batch.delete(caseRef);
      }

      await batch.commit();
      if (isLastBatch) break;
    }
  }

  Future<void> updateCaseStatus(
    String caseId,
    Map<String, dynamic> data,
  ) async {
    await _db.collection('cases').doc(caseId).update({
      ...data,
      'lastUpdated': FieldValue.serverTimestamp(),
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
