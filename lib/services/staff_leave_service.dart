import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import 'staff_assignment_service.dart';

class StaffLeaveService {
  final FirebaseFirestore _db;

  StaffLeaveService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOwnLeaves(String staffId) =>
      _db
          .collection('staffLeaves')
          .where('staffId', isEqualTo: staffId)
          .snapshots();

  Future<int> fileLeave({
    required UserModel staff,
    required DateTime endsAt,
    required String reasonCode,
    required String reasonLabel,
    String note = '',
  }) async {
    if (!staff.isStaff) {
      throw StateError('Only Barangay Staff accounts can file staff leave.');
    }
    final now = DateTime.now();
    if (!endsAt.isAfter(now)) {
      throw StateError('The leave end date and time must be in the future.');
    }
    if (reasonCode.trim().isEmpty || reasonLabel.trim().isEmpty) {
      throw StateError('Select a reason for leave.');
    }
    if (reasonCode == 'other' && note.trim().isEmpty) {
      throw StateError('Enter a note for the selected reason.');
    }

    final profilesSnapshot = await _db
        .collection('staffAssignmentProfiles')
        .where('active', isEqualTo: true)
        .get();
    final profiles = profilesSnapshot.docs
        .map((doc) => {...doc.data(), 'staffId': doc.id})
        .toList();
    final openCasesSnapshot = await _db
        .collection('cases')
        .where('assignedStaffId', isEqualTo: staff.uid)
        .get();
    final openCases =
        openCasesSnapshot.docs.where((doc) {
          final status = (doc.data()['status'] ?? '').toString();
          return !assignmentTerminalStatuses.contains(status);
        }).toList()..sort((a, b) {
          final aDate = (a.data()['slaDeadline'] as Timestamp?)?.toDate();
          final bDate = (b.data()['slaDeadline'] as Timestamp?)?.toDate();
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        });

    final available = profiles.where((profile) {
      if (profile['staffId'] == staff.uid) return false;
      final leaveUntil = profile['leaveUntil'];
      return leaveUntil is! Timestamp || !leaveUntil.toDate().isAfter(now);
    }).toList();
    if (openCases.isNotEmpty && available.isEmpty) {
      throw StateError(
        'Leave cannot start while this is the only active staff account with open assignments.',
      );
    }

    final virtualProfiles = available
        .map((profile) => Map<String, dynamic>.from(profile))
        .toList();
    final assignments = <String, StaffAssignmentPlan>{};
    for (final serviceRequest in openCases) {
      final data = serviceRequest.data();
      final weight =
          (data['assignmentWeight'] as num?)?.toDouble() ??
          StaffAssignmentService.workloadWeight(
            submittedAt:
                (data['submissionTimestamp'] as Timestamp?)?.toDate() ?? now,
            deadline: (data['slaDeadline'] as Timestamp?)?.toDate(),
          );
      final plan = StaffAssignmentService.selectFairest(
        virtualProfiles,
        caseWeight: weight,
        now: now,
      );
      if (plan == null) continue;
      assignments[serviceRequest.id] = plan;
      final selected = virtualProfiles.firstWhere(
        (profile) => profile['staffId'] == plan.staffId,
      );
      selected['workloadPoints'] = plan.workloadPoints + weight;
      selected['openCaseCount'] = plan.openCaseCount + 1;
      selected['lastAssignedAt'] = Timestamp.fromDate(now);
    }

    final leaveRef = _db.collection('staffLeaves').doc();
    final batch = _db.batch();
    batch.set(leaveRef, {
      'leaveId': leaveRef.id,
      'staffId': staff.uid,
      'staffName': staff.name,
      'reasonCode': reasonCode.trim(),
      'reasonLabel': reasonLabel.trim(),
      'note': note.trim(),
      'startsAt': FieldValue.serverTimestamp(),
      'endsAt': Timestamp.fromDate(endsAt),
      'filedAt': FieldValue.serverTimestamp(),
      'redistributedCaseCount': assignments.length,
    });
    batch.set(
      _db.collection('staffAssignmentProfiles').doc(staff.uid),
      {
        'staffId': staff.uid,
        'staffName': staff.name,
        'active': staff.isActive,
        'leaveUntil': Timestamp.fromDate(endsAt),
        'leaveReason': reasonLabel.trim(),
        'openCaseCount': 0,
        'workloadPoints': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    for (final entry in assignments.entries) {
      final caseRef = _db.collection('cases').doc(entry.key);
      final plan = entry.value;
      batch.update(caseRef, {
        ...StaffAssignmentService.caseAssignmentFields(plan),
        'reassignedFromStaffId': staff.uid,
        'reassignedFromStaffName': staff.name,
        'reassignmentReason': 'Staff leave',
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      batch.set(caseRef.collection('actionLog').doc(), {
        'action': 'Service request reassigned due to staff leave',
        'staffId': staff.uid,
        'staffName': staff.name,
        'staffRole': staff.role,
        'assignedToId': plan.staffId,
        'assignedToName': plan.staffName,
        'timestamp': FieldValue.serverTimestamp(),
      });
      final notification = _db.collection('notifications').doc();
      batch.set(notification, {
        'type': 'case_assigned',
        'title': 'Service request reassigned to you',
        'message':
            'An open service request was reassigned because ${staff.name} filed leave.',
        'caseId': entry.key,
        'referenceNumber':
            (openCases
                        .firstWhere(
                          (serviceRequest) => serviceRequest.id == entry.key,
                        )
                        .data()['referenceNumber'] ??
                    '')
                .toString(),
        'recipientId': plan.staffId,
        'audienceRoles': const <String>[],
        'createdById': staff.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String>[],
        'deletedBy': <String>[],
      });
    }
    for (final profile in virtualProfiles) {
      batch.set(
        _db.collection('staffAssignmentProfiles').doc(profile['staffId']),
        {
          'openCaseCount': profile['openCaseCount'] ?? 0,
          'workloadPoints': profile['workloadPoints'] ?? 0,
          if (profile['lastAssignedAt'] != null)
            'lastAssignedAt': profile['lastAssignedAt'],
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    return assignments.length;
  }
}
