import 'package:cloud_firestore/cloud_firestore.dart';

class CaseModel {
  final String? id;
  final String referenceNumber;
  final String residentId;
  final String residentName;
  final String residentMobile;
  final String residentAddress;
  final Map<String, dynamic>? addressLocation;
  final bool requestedForSelf;
  final String requesterName;
  final String requesterMobile;
  final String serviceCategory;
  final String serviceSubType;
  final String status;
  final String submissionChannel;
  final String? encodedById;
  final String? encodedByName;
  final String? encodedByRole;
  final DateTime submissionTimestamp;
  final DateTime? lastUpdated;
  final String? assignedStaffId;
  final DateTime? slaDeadline;
  final String slaStatus;
  final bool isConfidential;
  final List<Map<String, dynamic>> documents;
  final double? assistanceAmount;
  final String? budgetProgramId;

  CaseModel({
    this.id,
    this.referenceNumber = '',
    required this.residentId,
    required this.residentName,
    required this.residentMobile,
    required this.residentAddress,
    this.addressLocation,
    this.requestedForSelf = true,
    this.requesterName = '',
    this.requesterMobile = '',
    required this.serviceCategory,
    required this.serviceSubType,
    this.status = 'pending_review',
    this.submissionChannel = 'portal',
    this.encodedById,
    this.encodedByName,
    this.encodedByRole,
    DateTime? submissionTimestamp,
    this.lastUpdated,
    this.assignedStaffId,
    this.slaDeadline,
    this.slaStatus = 'on_time',
    this.isConfidential = false,
    this.documents = const [],
    this.assistanceAmount,
    this.budgetProgramId,
  }) : submissionTimestamp = submissionTimestamp ?? DateTime.now();

  factory CaseModel.fromMap(Map<String, dynamic> map, String id) {
    return CaseModel(
      id: id,
      referenceNumber: map['referenceNumber'] ?? '',
      residentId: map['residentId'] ?? '',
      residentName: map['residentName'] ?? '',
      residentMobile: map['residentMobile'] ?? '',
      residentAddress: map['residentAddress'] ?? '',
      addressLocation: map['addressLocation'] is Map
          ? Map<String, dynamic>.from(map['addressLocation'] as Map)
          : null,
      requestedForSelf: map['requestedForSelf'] != false,
      requesterName: map['requesterName'] ?? map['residentName'] ?? '',
      requesterMobile: map['requesterMobile'] ?? map['residentMobile'] ?? '',
      serviceCategory: map['serviceCategory'] ?? '',
      serviceSubType: map['serviceSubType'] ?? '',
      status: map['status'] ?? 'pending_review',
      submissionChannel: map['submissionChannel'] ?? 'portal',
      encodedById: map['encodedById'],
      encodedByName: map['encodedByName'],
      encodedByRole: map['encodedByRole'],
      submissionTimestamp: map['submissionTimestamp'] is Timestamp
          ? (map['submissionTimestamp'] as Timestamp).toDate()
          : DateTime.now(),
      lastUpdated: map['lastUpdated'] is Timestamp
          ? (map['lastUpdated'] as Timestamp).toDate()
          : null,
      assignedStaffId: map['assignedStaffId'],
      slaDeadline: map['slaDeadline'] is Timestamp
          ? (map['slaDeadline'] as Timestamp).toDate()
          : null,
      slaStatus: map['slaStatus'] ?? 'on_time',
      isConfidential: map['isConfidential'] ?? false,
      documents: List<Map<String, dynamic>>.from(map['documents'] ?? []),
      assistanceAmount: (map['assistanceAmount'] as num?)?.toDouble(),
      budgetProgramId: map['budgetProgramId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'referenceNumber': referenceNumber,
      'residentId': residentId,
      'residentName': residentName,
      'residentMobile': residentMobile,
      'residentAddress': residentAddress,
      if (addressLocation != null) ...{
        'addressLocation': addressLocation,
        'location': GeoPoint(
          (addressLocation!['latitude'] as num).toDouble(),
          (addressLocation!['longitude'] as num).toDouble(),
        ),
      },
      'requestedForSelf': requestedForSelf,
      'requesterName': requesterName,
      'requesterMobile': requesterMobile,
      'serviceCategory': serviceCategory,
      'serviceSubType': serviceSubType,
      'status': status,
      'submissionChannel': submissionChannel,
      if (encodedById != null) 'encodedById': encodedById,
      if (encodedByName != null) 'encodedByName': encodedByName,
      if (encodedByRole != null) 'encodedByRole': encodedByRole,
      'submissionTimestamp': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'slaDeadline': slaDeadline,
      'slaStatus': slaStatus,
      'isConfidential': isConfidential,
      'documents': documents,
      if (assistanceAmount != null) 'assistanceAmount': assistanceAmount,
      if (budgetProgramId != null) 'budgetProgramId': budgetProgramId,
    };
  }
}
