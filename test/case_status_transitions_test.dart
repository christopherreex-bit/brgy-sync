import 'package:brgysync_app/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved cases must pass through for claiming before release', () {
    expect(validNextCaseStatuses(statusApproved), contains(statusForClaiming));
    expect(
      validNextCaseStatuses(statusApproved),
      isNot(contains(statusReleased)),
    );
    expect(validNextCaseStatuses(statusForClaiming), contains(statusReleased));
  });

  test('released remains a terminal status', () {
    expect(validNextCaseStatuses(statusReleased), isEmpty);
  });

  test('processing no longer offers awaiting documents', () {
    expect(
      validNextCaseStatuses(statusProcessing),
      isNot(contains(statusAwaitingDocs)),
    );
    expect(validNextCaseStatuses(statusProcessing), contains(statusApproved));
  });

  test('legacy awaiting-document cases can still move forward', () {
    expect(
      validNextCaseStatuses(statusAwaitingDocs),
      containsAll([statusProcessing, statusApproved, statusRejected]),
    );
  });
}
