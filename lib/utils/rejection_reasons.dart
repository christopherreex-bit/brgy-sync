const Map<String, String> rejectionReasonLabels = {
  'ineligible': 'Ineligible for the requested service',
  'insufficient_funds': 'Insufficient available funds',
  'not_resident': 'Not a resident of Barangay Calzada-Tipas',
  'duplicate_request': 'Duplicate service request',
  'outside_service_scope': 'Request is outside the barangay’s service scope',
  'information_not_verified': 'Information could not be verified',
  'requirements_not_met': 'Eligibility requirements were not met',
  'withdrawn_by_resident': 'Withdrawn by the resident',
  'other': 'Other reason',
};

String rejectionReasonLabel(String? code) =>
    rejectionReasonLabels[code] ?? 'Unspecified legacy reason';
