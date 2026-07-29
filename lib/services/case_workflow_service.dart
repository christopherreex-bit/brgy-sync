import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/constants.dart';

class CaseWorkflowService {
  final FirebaseFirestore _db;

  CaseWorkflowService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<void> assignCase({
    required String caseId,
    required String assigneeId,
    required String assigneeName,
    required String actorId,
    required String actorName,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Enter a reason for the assignment.');
    }
    final caseRef = _db.collection('cases').doc(caseId);
    final logRef = caseRef.collection('actionLog').doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(caseRef);
      if (!snapshot.exists) throw StateError('Case not found.');
      final data = snapshot.data()!;
      final previousName = (data['assignedStaffName'] ?? 'Unassigned')
          .toString();
      transaction.update(caseRef, {
        'assignedStaffId': assigneeId,
        'assignedStaffName': assigneeName,
        'assignedAt': FieldValue.serverTimestamp(),
        'assignedBy': actorId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': data['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': actorId,
        'staffName': actorName,
        'action': 'Case assignment changed',
        'previousStatus': data['status'] ?? '',
        'newStatus': '',
        'notes': '$previousName → $assigneeName. $trimmedReason',
        'smsSent': false,
        'smsBody': '',
      });
    });
  }

  Future<void> verifyDocument({
    required String caseId,
    required int documentIndex,
    required String verificationStatus,
    required String reason,
    required String actorId,
    required String actorName,
  }) async {
    if (!['valid', 'invalid'].contains(verificationStatus)) {
      throw ArgumentError('Invalid document verification status.');
    }
    final trimmedReason = reason.trim();
    if (verificationStatus == 'invalid' && trimmedReason.isEmpty) {
      throw StateError('Enter why this document needs replacement.');
    }
    final caseRef = _db.collection('cases').doc(caseId);
    final logRef = caseRef.collection('actionLog').doc();
    final notificationRef = _db.collection('notifications').doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(caseRef);
      if (!snapshot.exists) throw StateError('Case not found.');
      final data = snapshot.data()!;
      final documents = List<Map<String, dynamic>>.from(
        data['documents'] ?? [],
      );
      if (documentIndex < 0 || documentIndex >= documents.length) {
        throw StateError('Document not found.');
      }
      final document = Map<String, dynamic>.from(documents[documentIndex]);
      document.addAll({
        'verificationStatus': verificationStatus,
        'verificationReason': trimmedReason,
        'verifiedBy': actorId,
        'verifiedByName': actorName,
        'verifiedAt': Timestamp.now(),
      });
      documents[documentIndex] = document;
      final hasInvalid = documents.any(
        (item) => item['verificationStatus'] == 'invalid',
      );
      transaction.update(caseRef, {
        'documents': documents,
        'residentActionRequired': hasInvalid,
        'correctionRequestedAt': hasInvalid
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      final documentName = (document['name'] ?? 'Document').toString();
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': data['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': actorId,
        'staffName': actorName,
        'action': verificationStatus == 'valid'
            ? 'Document verified'
            : 'Document replacement requested',
        'previousStatus': data['status'] ?? '',
        'newStatus': '',
        'notes':
            '$documentName${trimmedReason.isEmpty ? '' : ': $trimmedReason'}',
        'smsSent': false,
        'smsBody': '',
      });
      if (verificationStatus == 'invalid') {
        transaction.set(notificationRef, {
          'residentId': data['residentId'] ?? '',
          'caseId': caseId,
          'referenceNumber': data['referenceNumber'] ?? '',
          'type': 'document_correction',
          'title': 'Document replacement required',
          'message': '$documentName: $trimmedReason',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> replaceDocument({
    required String caseId,
    required int documentIndex,
    required Map<String, dynamic> replacement,
    required String residentId,
    required String residentName,
  }) async {
    final caseRef = _db.collection('cases').doc(caseId);
    final logRef = caseRef.collection('actionLog').doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(caseRef);
      if (!snapshot.exists) throw StateError('Case not found.');
      final data = snapshot.data()!;
      if (data['residentId'] != residentId) {
        throw StateError('You cannot update this case.');
      }
      final documents = List<Map<String, dynamic>>.from(
        data['documents'] ?? [],
      );
      if (documentIndex < 0 || documentIndex >= documents.length) {
        throw StateError('Document not found.');
      }
      final oldDocument = documents[documentIndex];
      if (oldDocument['verificationStatus'] != 'invalid') {
        throw StateError('This document is not awaiting replacement.');
      }
      documents[documentIndex] = {
        ...replacement,
        'name': oldDocument['name'] ?? replacement['name'] ?? 'Document',
        'required': oldDocument['required'] == true,
        'verificationStatus': 'pending',
        'verificationReason': '',
        'replacedAt': Timestamp.now(),
      };
      final hasInvalid = documents.any(
        (item) => item['verificationStatus'] == 'invalid',
      );
      transaction.update(caseRef, {
        'documents': documents,
        'residentActionRequired': hasInvalid,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': data['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': residentId,
        'staffName': residentName,
        'action': 'Resident replaced requested document',
        'previousStatus': data['status'] ?? '',
        'newStatus': '',
        'notes': documents[documentIndex]['name'] ?? 'Document',
        'smsSent': false,
        'smsBody': '',
      });
    });
  }

  Future<void> cancelCase({
    required String caseId,
    required String residentId,
    required String residentName,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) throw StateError('Enter a cancellation reason.');
    final caseRef = _db.collection('cases').doc(caseId);
    final logRef = caseRef.collection('actionLog').doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(caseRef);
      if (!snapshot.exists) throw StateError('Case not found.');
      final data = snapshot.data()!;
      if (data['residentId'] != residentId) {
        throw StateError('You cannot cancel this case.');
      }
      final status = normalizeCaseStatus((data['status'] ?? '').toString());
      if (![statusPendingReview, statusProcessing].contains(status)) {
        throw StateError(
          'Only Pending Review or Processing cases can be cancelled.',
        );
      }
      transaction.update(caseRef, {
        'status': statusRejected,
        'residentCancelled': true,
        'residentCancellationReason': trimmedReason,
        'residentCancelledAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': data['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': residentId,
        'staffName': residentName,
        'action': 'Case cancelled by resident',
        'previousStatus': status,
        'newStatus': statusRejected,
        'notes': trimmedReason,
        'smsSent': false,
        'smsBody': '',
      });
    });
  }

  Future<void> submitFeedback({
    required String caseId,
    required String residentId,
    required int rating,
    required String comment,
    required bool improperRequestReported,
  }) async {
    if (rating < 1 || rating > 5) {
      throw StateError('Select a rating from 1 to 5.');
    }
    final caseRef = _db.collection('cases').doc(caseId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(caseRef);
      if (!snapshot.exists) throw StateError('Case not found.');
      final data = snapshot.data()!;
      if (data['residentId'] != residentId ||
          normalizeCaseStatus((data['status'] ?? '').toString()) !=
              statusReleased) {
        throw StateError('Feedback is only available for your released case.');
      }
      transaction.update(caseRef, {
        'residentFeedback': {
          'rating': rating,
          'comment': comment.trim(),
          'improperRequestReported': improperRequestReported,
          'submittedAt': Timestamp.now(),
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }
}
