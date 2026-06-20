import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/case_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Cases ────────────────────────────────────────────────────
  Future<String> createCase(CaseModel caseData) async {
    final year = DateTime.now().year;
    final snapshot = await _db
        .collection('cases')
        .where('referenceNumber', isGreaterThanOrEqualTo: 'BRGY-$year-')
        .where('referenceNumber', isLessThan: 'BRGY-${year + 1}-')
        .orderBy('referenceNumber', descending: true)
        .limit(1)
        .get();

    int nextNum = 1;
    if (snapshot.docs.isNotEmpty) {
      final lastRef = snapshot.docs.first.data()['referenceNumber'] as String;
      final parts = lastRef.split('-');
      final lastPart = parts.last;
      nextNum = (int.tryParse(lastPart) ?? 0) + 1;
    }

    final refNumber = 'BRGY-$year-${nextNum.toString().padLeft(5, '0')}';
    final docRef = _db.collection('cases').doc();
    await docRef.set(caseData.toMap()..['referenceNumber'] = refNumber);
    return refNumber;
  }

  Stream<QuerySnapshot> getCases({String? statusFilter}) {
    Query query = _db.collection('cases').orderBy('submissionTimestamp', descending: true);
    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    return query.snapshots();
  }

  Future<DocumentSnapshot> getCase(String caseId) {
    return _db.collection('cases').doc(caseId).get();
  }

  Future<void> updateCaseStatus(String caseId, Map<String, dynamic> data) async {
    await _db.collection('cases').doc(caseId).update({
      ...data,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addActionLog(String caseId, Map<String, dynamic> logData) async {
    await _db
        .collection('cases')
        .doc(caseId)
        .collection('actionLog')
        .add({
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
    return _db.collection('reports').orderBy('generatedAt', descending: true).snapshots();
  }
}
