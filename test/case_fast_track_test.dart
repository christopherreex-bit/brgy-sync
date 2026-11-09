import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/utils/case_fast_track.dart';
import 'package:brgysync_app/utils/constants.dart';

void main() {
  Map<String, dynamic> eligibleCase() => {
    'status': statusPendingReview,
    'serviceCategory': 'documents',
    'serviceSubType': 'Barangay Clearance',
    'requestedForSelf': true,
    'registryMatchStatus': 'verified_match',
    'repeatSubmission': false,
    'documents': <Map<String, dynamic>>[],
  };

  test('verified self-filed clearance can skip processing', () {
    final data = eligibleCase();
    expect(isVerifiedDocumentFastTrackEligible(data), isTrue);
    expect(validNextStatusesForCase(data), contains(statusApproved));
  });

  test('unverified clearance must use the normal processing step', () {
    final data = eligibleCase()..['registryMatchStatus'] = 'needs_review';
    expect(isVerifiedDocumentFastTrackEligible(data), isFalse);
    expect(validNextStatusesForCase(data), isNot(contains(statusApproved)));
  });

  test('request for another person is not eligible', () {
    final data = eligibleCase()..['requestedForSelf'] = false;
    expect(isVerifiedDocumentFastTrackEligible(data), isFalse);
  });

  test('other service types cannot skip processing', () {
    final data = eligibleCase()..['serviceSubType'] = 'Barangay ID';
    expect(isVerifiedDocumentFastTrackEligible(data), isFalse);
  });

  test('missing required documents prevent fast track', () {
    final data = eligibleCase()
      ..['documents'] = <Map<String, dynamic>>[
        {'required': true, 'status': 'missing'},
      ];
    expect(isVerifiedDocumentFastTrackEligible(data), isFalse);
  });
}
