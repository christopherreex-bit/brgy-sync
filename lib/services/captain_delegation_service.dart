import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class CaptainDelegationService {
  final FirebaseFirestore _db;

  CaptainDelegationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _current =>
      _db.collection('captainDelegations').doc('current');

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCurrent() =>
      _current.snapshots();

  Future<void> grant({
    required UserModel captain,
    required String delegateUid,
    required String delegateName,
    required String delegateRole,
    required DateTime expiresAt,
    required String reason,
  }) async {
    if (!captain.isPermanentCaptain) {
      throw StateError(
        'Only the permanent Barangay Captain can delegate access.',
      );
    }
    if (!['staff', 'officer'].contains(delegateRole)) {
      throw StateError(
        'Acting Captain access can only be given to active staff or officers.',
      );
    }
    if (!expiresAt.isAfter(DateTime.now())) {
      throw StateError('The delegation expiry must be in the future.');
    }
    if (reason.trim().isEmpty) {
      throw StateError('Enter a reason for the delegation.');
    }
    final event = _db.collection('captainDelegationEvents').doc();
    final batch = _db.batch();
    final delegation = {
      'active': true,
      'delegateUid': delegateUid,
      'delegateName': delegateName,
      'delegateRole': delegateRole,
      'startsAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'reason': reason.trim(),
      'grantedBy': captain.uid,
      'grantedByName': captain.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    batch.set(_current, delegation);
    batch.set(event, {
      ...delegation,
      'eventType': 'granted',
      'eventId': event.id,
    });
    await batch.commit();
  }

  Future<void> revoke({required UserModel captain}) async {
    if (!captain.isPermanentCaptain) {
      throw StateError(
        'Only the permanent Barangay Captain can revoke access.',
      );
    }
    final event = _db.collection('captainDelegationEvents').doc();
    final batch = _db.batch();
    batch.update(_current, {
      'active': false,
      'revokedAt': FieldValue.serverTimestamp(),
      'revokedBy': captain.uid,
      'revokedByName': captain.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(event, {
      'eventType': 'revoked',
      'eventId': event.id,
      'actorId': captain.uid,
      'actorName': captain.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> changeExpiry({
    required UserModel captain,
    required DateTime expiresAt,
    required String reason,
  }) async {
    if (!captain.isPermanentCaptain) {
      throw StateError(
        'Only the permanent Barangay Captain can change the duration.',
      );
    }
    if (!expiresAt.isAfter(DateTime.now())) {
      throw StateError('The new expiry must be in the future.');
    }
    if (reason.trim().isEmpty) {
      throw StateError('Enter a reason for changing the duration.');
    }
    final event = _db.collection('captainDelegationEvents').doc();
    await _db.runTransaction((transaction) async {
      final current = await transaction.get(_current);
      if (!current.exists || current.data()?['active'] != true) {
        throw StateError('There is no active delegation to update.');
      }
      final data = current.data()!;
      transaction.update(_current, {
        'expiresAt': Timestamp.fromDate(expiresAt),
        'durationChangeReason': reason.trim(),
        'durationChangedAt': FieldValue.serverTimestamp(),
        'durationChangedBy': captain.uid,
        'durationChangedByName': captain.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(event, {
        'eventType': 'duration_changed',
        'eventId': event.id,
        'delegateUid': data['delegateUid'],
        'delegateName': data['delegateName'],
        'previousExpiresAt': data['expiresAt'],
        'expiresAt': Timestamp.fromDate(expiresAt),
        'reason': reason.trim(),
        'actorId': captain.uid,
        'actorName': captain.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
