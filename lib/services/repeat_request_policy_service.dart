import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/constants.dart';

class PriorRequestSummary {
  final String id;
  final String referenceNumber;
  final String status;
  final String serviceSubType;
  final DateTime? submittedAt;
  final String rejectionReason;

  const PriorRequestSummary({
    required this.id,
    required this.referenceNumber,
    required this.status,
    required this.serviceSubType,
    this.submittedAt,
    this.rejectionReason = '',
  });

  Map<String, dynamic> toMap() => {
    'caseId': id,
    'referenceNumber': referenceNumber,
    'status': status,
    'serviceSubType': serviceSubType,
    if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
    if (rejectionReason.isNotEmpty) 'rejectionReason': rejectionReason,
  };
}

class RepeatRequestDecision {
  final bool blocked;
  final String code;
  final String message;
  final List<PriorRequestSummary> relatedRequests;

  const RepeatRequestDecision({
    required this.blocked,
    required this.code,
    required this.message,
    this.relatedRequests = const [],
  });

  bool get shouldFlag => !blocked && relatedRequests.isNotEmpty;
}

/// Applies repeat-submission rules before a new service request is created.
///
/// Active duplicates are blocked for every service. Education Incentive is
/// limited to one accepted request per calendar/fiscal year. A prior rejection
/// never causes automatic rejection because the resident's eligibility or
/// supporting information may have changed; it is instead disclosed to staff.
class RepeatRequestPolicyService {
  RepeatRequestPolicyService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const Set<String> _activeStatuses = {
    statusPendingReview,
    statusProcessing,
    statusNeedsCorrection,
    statusApproved,
    statusForClaiming,
  };

  Future<RepeatRequestDecision> evaluate({
    required String residentId,
    required String residentMobile,
    required String serviceCategory,
    required String serviceSubType,
    DateTime? now,
  }) async {
    final byId = await _db
        .collection('cases')
        .where('residentId', isEqualTo: residentId)
        .get();
    final unique = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in byId.docs) {
      unique[doc.id] = doc;
    }

    final sameService = unique.values.where((doc) {
      final data = doc.data();
      return _normalize(data['serviceCategory']) ==
              _normalize(serviceCategory) &&
          _normalize(data['serviceSubType']) == _normalize(serviceSubType);
    }).toList();
    sameService.sort((a, b) {
      final aDate = _date(a.data()['submissionTimestamp']);
      final bDate = _date(b.data()['submissionTimestamp']);
      return (bDate ?? DateTime(1970)).compareTo(aDate ?? DateTime(1970));
    });

    final normalizedCategory = _normalize(serviceCategory);
    final normalizedSubType = _normalize(serviceSubType);
    final isBirthdayEnrollment =
        normalizedCategory == 'beneficiary' &&
        {
          'senior citizen birthday program',
          'pwd birthday program',
        }.contains(normalizedSubType);

    final active = sameService.where((doc) {
      return _activeStatuses.contains(
        normalizeCaseStatus((doc.data()['status'] ?? '').toString()),
      );
    }).toList();
    if (active.isNotEmpty) {
      final prior = _summary(active.first);
      final isRevision = prior.status == statusNeedsCorrection;
      return RepeatRequestDecision(
        blocked: true,
        code: isRevision ? 'revise_existing_request' : 'active_duplicate',
        message: isRevision
            ? 'Service request ${prior.referenceNumber} is already For Revision. Open My Service Requests and revise that request instead of starting a new one.'
            : isBirthdayEnrollment
            ? 'You already have an active ${prior.serviceSubType} enrollment (${prior.referenceNumber}). Once approved, this same enrollment is used for recurring annual birthday incentives, so do not submit another application.'
            : 'You already have an active ${prior.serviceSubType} service request (${prior.referenceNumber}). Please wait for it to be completed before submitting another.',
        relatedRequests: [prior],
      );
    }

    final currentDate = now ?? DateTime.now();
    if (isBirthdayEnrollment) {
      final acceptedEnrollment = sameService.where((doc) {
        final status = normalizeCaseStatus(
          (doc.data()['status'] ?? '').toString(),
        );
        return {
          statusApproved,
          statusForClaiming,
          statusReleased,
        }.contains(status);
      }).toList();
      if (acceptedEnrollment.isNotEmpty) {
        final prior = _summary(acceptedEnrollment.first);
        return RepeatRequestDecision(
          blocked: true,
          code: 'active_birthday_program_enrollment',
          message:
              'You already have an approved ${prior.serviceSubType} enrollment (${prior.referenceNumber}). This enrollment remains active for annual birthday incentives, so you do not need to apply again.',
          relatedRequests: [prior],
        );
      }
    }
    if (normalizedCategory == 'education') {
      final acceptedThisYear = sameService.where((doc) {
        final data = doc.data();
        final submittedAt = _date(data['submissionTimestamp']);
        final status = normalizeCaseStatus((data['status'] ?? '').toString());
        return submittedAt?.year == currentDate.year &&
            {
              statusApproved,
              statusForClaiming,
              statusReleased,
            }.contains(status);
      }).toList();
      if (acceptedThisYear.isNotEmpty) {
        final prior = _summary(acceptedThisYear.first);
        return RepeatRequestDecision(
          blocked: true,
          code: 'education_yearly_limit',
          message:
              'Education Incentive may only be accepted once per calendar year. ${prior.referenceNumber} was already ${_statusLabel(prior.status)} in ${currentDate.year}. You may apply again next year.',
          relatedRequests: [prior],
        );
      }
    }

    if (_normalize(serviceCategory) == 'documents' &&
        _normalize(serviceSubType) == 'indigency certificate') {
      final validIssuedCertificate = sameService.where((doc) {
        final data = doc.data();
        final issuedAt = _date(data['certificateIssuedAt']);
        return normalizeCaseStatus((data['status'] ?? '').toString()) ==
                statusReleased &&
            data['certificateIssuanceStatus'] == 'issued' &&
            issuedAt != null &&
            issuedAt.add(const Duration(days: 60)).isAfter(currentDate);
      }).toList();
      if (validIssuedCertificate.isNotEmpty) {
        final prior = _summary(validIssuedCertificate.first);
        return RepeatRequestDecision(
          blocked: true,
          code: 'valid_indigency_certificate_exists',
          message:
              'You already have a valid Certificate of Indigency from ${prior.referenceNumber}. Open My Record to view or print it; a new request is unnecessary until it expires.',
          relatedRequests: [prior],
        );
      }
    }

    final completedOrRejected = sameService
        .where((doc) {
          final status = normalizeCaseStatus(
            (doc.data()['status'] ?? '').toString(),
          );
          return status == statusRejected || status == statusReleased;
        })
        .map(_summary)
        .toList();
    return RepeatRequestDecision(
      blocked: false,
      code: completedOrRejected.isEmpty ? 'first_submission' : 'staff_review',
      message: completedOrRejected.isEmpty
          ? ''
          : 'A previous request for the same service exists. Staff must review its outcome before deciding this request.',
      relatedRequests: completedOrRejected.take(5).toList(),
    );
  }

  static PriorRequestSummary _summary(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final reason = (data['rejectionReasonLabel'] ?? data['statusReason'] ?? '')
        .toString()
        .trim();
    return PriorRequestSummary(
      id: doc.id,
      referenceNumber: (data['referenceNumber'] ?? doc.id).toString(),
      status: normalizeCaseStatus((data['status'] ?? '').toString()),
      serviceSubType: (data['serviceSubType'] ?? 'same service').toString(),
      submittedAt: _date(data['submissionTimestamp']),
      rejectionReason: reason,
    );
  }

  static DateTime? _date(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;

  static String _normalize(Object? value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static String _statusLabel(String status) => status
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
