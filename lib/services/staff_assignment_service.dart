import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/case_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

const Set<String> assignmentTerminalStatuses = {'released', 'rejected'};

class StaffAssignmentPlan {
  final String staffId;
  final String staffName;
  final double workloadPoints;
  final int openCaseCount;
  final double caseWeight;

  const StaffAssignmentPlan({
    required this.staffId,
    required this.staffName,
    required this.workloadPoints,
    required this.openCaseCount,
    required this.caseWeight,
  });
}

class StaffAssignmentService {
  final FirebaseFirestore _db;

  StaffAssignmentService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  static double workloadWeight({
    required DateTime submittedAt,
    required DateTime? deadline,
  }) {
    final minutes = deadline?.difference(submittedAt).inMinutes ?? 60;
    if (minutes <= 0) return 4;
    // One hour is the neutral unit. Urgent 15-minute documentary services
    // count as four workload points, while long-running services retain a
    // floor of half a point. This respects SLA pressure without allowing a
    // single short request to distort assignments for an entire shift.
    return (60 / minutes).clamp(0.5, 4).toDouble();
  }

  static bool isPendingAssignmentStatus(String rawStatus) {
    final status = normalizeCaseStatus(rawStatus);
    return status == statusPendingReview ||
        status == statusProcessing ||
        status == statusNeedsCorrection ||
        status == statusAwaitingDocs;
  }

  static StaffAssignmentPlan? selectFairest(
    Iterable<Map<String, dynamic>> profiles, {
    required double caseWeight,
    DateTime? now,
    String? excludingStaffId,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final eligible = profiles.where((profile) {
      if (profile['active'] == false ||
          profile['staffId'] == excludingStaffId) {
        return false;
      }
      final leaveUntil = profile['leaveUntil'];
      return leaveUntil is! Timestamp ||
          !leaveUntil.toDate().isAfter(effectiveNow);
    }).toList();
    if (eligible.isEmpty) return null;

    eligible.sort((a, b) {
      final loadA = (a['workloadPoints'] as num?)?.toDouble() ?? 0;
      final loadB = (b['workloadPoints'] as num?)?.toDouble() ?? 0;
      final loadComparison = loadA.compareTo(loadB);
      if (loadComparison != 0) return loadComparison;
      final countA = (a['openCaseCount'] as num?)?.toInt() ?? 0;
      final countB = (b['openCaseCount'] as num?)?.toInt() ?? 0;
      final countComparison = countA.compareTo(countB);
      if (countComparison != 0) return countComparison;
      final assignedA = (a['lastAssignedAt'] as Timestamp?)?.toDate();
      final assignedB = (b['lastAssignedAt'] as Timestamp?)?.toDate();
      if (assignedA == null && assignedB != null) return -1;
      if (assignedA != null && assignedB == null) return 1;
      if (assignedA != null && assignedB != null) {
        final dateComparison = assignedA.compareTo(assignedB);
        if (dateComparison != 0) return dateComparison;
      }
      return (a['staffId'] ?? '').toString().compareTo(
        (b['staffId'] ?? '').toString(),
      );
    });
    final selected = eligible.first;
    return StaffAssignmentPlan(
      staffId: selected['staffId'].toString(),
      staffName: (selected['staffName'] ?? 'Barangay Staff').toString(),
      workloadPoints: (selected['workloadPoints'] as num?)?.toDouble() ?? 0,
      openCaseCount: (selected['openCaseCount'] as num?)?.toInt() ?? 0,
      caseWeight: caseWeight,
    );
  }

  Future<void> ensureStaffProfile(UserModel user) async {
    if (!user.isStaff) return;
    await _db.collection('staffAssignmentProfiles').doc(user.uid).set({
      'staffId': user.uid,
      'staffName': user.name,
      'active': user.isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      'openCaseCount': FieldValue.increment(0),
      'workloadPoints': FieldValue.increment(0),
    }, SetOptions(merge: true));
  }

  Future<StaffAssignmentPlan?> plan(CaseModel serviceRequest) async {
    final snapshot = await _db
        .collection('staffAssignmentProfiles')
        .where('active', isEqualTo: true)
        .get();
    final weight = workloadWeight(
      submittedAt: serviceRequest.submissionTimestamp,
      deadline: serviceRequest.slaDeadline,
    );
    return selectFairest(
      snapshot.docs.map((doc) => {...doc.data(), 'staffId': doc.id}),
      caseWeight: weight,
    );
  }

  /// Assigns older, still-actionable requests that predate automatic
  /// assignment. Approved and terminal requests are deliberately excluded.
  Future<int> assignExistingPendingRequests({
    required String actorId,
    required String actorName,
    required String actorRole,
  }) async {
    final results = await Future.wait([
      _db
          .collection('staffAssignmentProfiles')
          .where('active', isEqualTo: true)
          .get(),
      _db.collection('cases').get(),
    ]);
    final profileSnapshot = results[0];
    final caseSnapshot = results[1];
    final now = DateTime.now();
    final profiles = profileSnapshot.docs
        .map((doc) => <String, dynamic>{...doc.data(), 'staffId': doc.id})
        .where((profile) {
          final leaveUntil = profile['leaveUntil'];
          return leaveUntil is! Timestamp || !leaveUntil.toDate().isAfter(now);
        })
        .toList();
    if (profiles.isEmpty) {
      throw StateError('No active staff account is available for assignment.');
    }

    final pending =
        caseSnapshot.docs.where((doc) {
          final data = doc.data();
          final assignedStaffId = (data['assignedStaffId'] ?? '')
              .toString()
              .trim();
          return assignedStaffId.isEmpty &&
              isPendingAssignmentStatus(
                (data['status'] ?? statusPendingReview).toString(),
              );
        }).toList()..sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aSubmitted =
              (aData['submissionTimestamp'] as Timestamp?)?.toDate() ?? now;
          final bSubmitted =
              (bData['submissionTimestamp'] as Timestamp?)?.toDate() ?? now;
          final aDeadline =
              (aData['slaDeadline'] as Timestamp?)?.toDate() ?? aSubmitted;
          final bDeadline =
              (bData['slaDeadline'] as Timestamp?)?.toDate() ?? bSubmitted;
          final deadlineComparison = aDeadline.compareTo(bDeadline);
          return deadlineComparison != 0
              ? deadlineComparison
              : aSubmitted.compareTo(bSubmitted);
        });

    if (pending.isEmpty) return 0;

    final planned =
        <
          MapEntry<
            QueryDocumentSnapshot<Map<String, dynamic>>,
            StaffAssignmentPlan
          >
        >[];
    for (final serviceRequest in pending) {
      final data = serviceRequest.data();
      final submittedAt =
          (data['submissionTimestamp'] as Timestamp?)?.toDate() ?? now;
      final deadline = (data['slaDeadline'] as Timestamp?)?.toDate();
      final weight = workloadWeight(
        submittedAt: submittedAt,
        deadline: deadline,
      );
      final plan = selectFairest(profiles, caseWeight: weight, now: now);
      if (plan == null) break;
      planned.add(MapEntry(serviceRequest, plan));
      final profile = profiles.firstWhere(
        (candidate) => candidate['staffId'] == plan.staffId,
      );
      profile['openCaseCount'] = plan.openCaseCount + 1;
      profile['workloadPoints'] = plan.workloadPoints + plan.caseWeight;
      profile['lastAssignedAt'] = Timestamp.fromDate(now);
    }

    // Each request uses three writes. Keeping chunks small leaves room for
    // the per-staff workload counter updates in the same atomic batch.
    for (var start = 0; start < planned.length; start += 120) {
      final end = start + 120 < planned.length ? start + 120 : planned.length;
      final chunk = planned.sublist(start, end);
      final countDeltas = <String, int>{};
      final weightDeltas = <String, double>{};
      final staffNames = <String, String>{};
      final batch = _db.batch();

      for (final assignment in chunk) {
        final serviceRequest = assignment.key;
        final plan = assignment.value;
        final data = serviceRequest.data();
        countDeltas.update(
          plan.staffId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        weightDeltas.update(
          plan.staffId,
          (value) => value + plan.caseWeight,
          ifAbsent: () => plan.caseWeight,
        );
        staffNames[plan.staffId] = plan.staffName;

        batch.update(serviceRequest.reference, {
          ...caseAssignmentFields(plan),
          'assignmentMethod': 'automatic_sla_balanced_backfill',
          'assignmentBackfilledAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        batch.set(serviceRequest.reference.collection('actionLog').doc(), {
          'action': 'Existing pending service request automatically assigned',
          'staffId': actorId,
          'staffName': actorName,
          'staffRole': actorRole,
          'assignedToId': plan.staffId,
          'assignedToName': plan.staffName,
          'timestamp': FieldValue.serverTimestamp(),
        });
        batch.set(_db.collection('notifications').doc(), {
          'type': 'case_assigned',
          'title': 'Existing service request assigned to you',
          'message':
              '${data['serviceSubType'] ?? 'A pending service request'} (${data['referenceNumber'] ?? ''}) was assigned to you.',
          'caseId': serviceRequest.id,
          'referenceNumber': (data['referenceNumber'] ?? '').toString(),
          'recipientId': plan.staffId,
          'audienceRoles': const <String>[],
          'createdById': actorId,
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String>[],
          'deletedBy': <String>[],
        });
      }

      for (final staffId in countDeltas.keys) {
        batch.set(
          _db.collection('staffAssignmentProfiles').doc(staffId),
          {
            'staffId': staffId,
            'staffName': staffNames[staffId] ?? 'Barangay Staff',
            'openCaseCount': FieldValue.increment(countDeltas[staffId]!),
            'workloadPoints': FieldValue.increment(weightDeltas[staffId]!),
            'lastAssignedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
    return planned.length;
  }

  static Map<String, dynamic> caseAssignmentFields(StaffAssignmentPlan? plan) =>
      plan == null
      ? {
          'assignmentStatus': 'waiting_for_available_staff',
          'assignmentMethod': 'automatic_sla_balanced',
        }
      : {
          'assignedStaffId': plan.staffId,
          'assignedStaffName': plan.staffName,
          'assignedAt': FieldValue.serverTimestamp(),
          'assignmentStatus': 'assigned',
          'assignmentMethod': 'automatic_sla_balanced',
          'assignmentWeight': plan.caseWeight,
        };
}
