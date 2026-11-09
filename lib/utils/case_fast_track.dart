import 'constants.dart';

/// Returns true only for simple document requests whose identity information
/// already came from a verified Citizen Registry record. Staff still makes
/// the approval decision; this only removes the redundant Processing step.
bool isVerifiedDocumentFastTrackEligible(Map<String, dynamic> caseData) {
  if (normalizeCaseStatus((caseData['status'] ?? '').toString()) !=
      statusPendingReview) {
    return false;
  }
  if ((caseData['serviceCategory'] ?? '').toString() != 'documents' ||
      (caseData['serviceSubType'] ?? '').toString() != 'Barangay Clearance') {
    return false;
  }
  if (caseData['requestedForSelf'] == false ||
      caseData['registryMatchStatus'] != 'verified_match' ||
      caseData['repeatSubmission'] == true) {
    return false;
  }

  final documents = List<Map<String, dynamic>>.from(
    caseData['documents'] as List? ?? const [],
  );
  return !documents.any(
    (document) =>
        document['required'] == true &&
        document['status'] != 'uploaded' &&
        document['status'] != 'reused',
  );
}

List<String> validNextStatusesForCase(Map<String, dynamic> caseData) {
  final currentStatus = (caseData['status'] ?? '').toString();
  final result = List<String>.from(validNextCaseStatuses(currentStatus));
  if (isVerifiedDocumentFastTrackEligible(caseData) &&
      !result.contains(statusApproved)) {
    result.insert(0, statusApproved);
  }
  return result;
}
