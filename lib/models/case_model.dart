import 'package:cloud_firestore/cloud_firestore.dart';

class CaseModel {
  final String? id;
  final String referenceNumber;
  final String residentId;
  final String residentName;
  final String residentMobile;
  final String residentAddress;
  final String serviceCategory;
  final String serviceSubType;
  final String status;
  final String submissionChannel;
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
    required this.serviceCategory,
    required this.serviceSubType,
    this.status = 'pending_review',
    this.submissionChannel = 'portal',
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
      serviceCategory: map['serviceCategory'] ?? '',
      serviceSubType: map['serviceSubType'] ?? '',
      status: map['status'] ?? 'pending_review',
      submissionChannel: map['submissionChannel'] ?? 'portal',
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
      'serviceCategory': serviceCategory,
      'serviceSubType': serviceSubType,
      'status': status,
      'submissionChannel': submissionChannel,
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
