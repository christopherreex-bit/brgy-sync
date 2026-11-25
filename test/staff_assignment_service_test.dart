import 'package:brgysync_app/services/staff_assignment_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short SLA service requests carry more workload weight', () {
    final submitted = DateTime(2026, 11, 25, 8);
    final documentWeight = StaffAssignmentService.workloadWeight(
      submittedAt: submitted,
      deadline: submitted.add(const Duration(minutes: 15)),
    );
    final multiDayWeight = StaffAssignmentService.workloadWeight(
      submittedAt: submitted,
      deadline: submitted.add(const Duration(days: 3)),
    );

    expect(documentWeight, greaterThan(multiDayWeight));
    expect(documentWeight, 4);
  });

  test('fairest selection chooses the lowest weighted active staff', () {
    final selected = StaffAssignmentService.selectFairest(
      [
        {
          'staffId': 'staff-a',
          'staffName': 'Staff A',
          'active': true,
          'workloadPoints': 5,
          'openCaseCount': 1,
        },
        {
          'staffId': 'staff-b',
          'staffName': 'Staff B',
          'active': true,
          'workloadPoints': 2,
          'openCaseCount': 3,
        },
      ],
      caseWeight: 1,
      now: DateTime(2026, 11, 25),
    );

    expect(selected?.staffId, 'staff-b');
  });

  test('staff whose leave has not ended is excluded', () {
    final now = DateTime(2026, 11, 25, 9);
    final selected = StaffAssignmentService.selectFairest(
      [
        {
          'staffId': 'on-leave',
          'staffName': 'On Leave',
          'active': true,
          'workloadPoints': 0,
          'openCaseCount': 0,
          'leaveUntil': Timestamp.fromDate(now.add(const Duration(days: 1))),
        },
        {
          'staffId': 'available',
          'staffName': 'Available',
          'active': true,
          'workloadPoints': 4,
          'openCaseCount': 2,
        },
      ],
      caseWeight: 1,
      now: now,
    );

    expect(selected?.staffId, 'available');
  });

  test('backfill accepts only pending actionable statuses', () {
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('pending_review'),
      isTrue,
    );
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('processing'),
      isTrue,
    );
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('needs_correction'),
      isTrue,
    );
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('awaiting_docs'),
      isTrue,
    );
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('approved'),
      isFalse,
    );
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('for_claiming'),
      isFalse,
    );
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('released'),
      isFalse,
    );
    expect(
      StaffAssignmentService.isPendingAssignmentStatus('rejected'),
      isFalse,
    );
  });
}
