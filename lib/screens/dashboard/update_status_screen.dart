import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/case_status_service.dart';
import '../../widgets/budget_approval_preview_dialog.dart';
import '../../utils/constants.dart';
import '../../utils/rejection_reasons.dart';
import '../../widgets/status_badge.dart';

class UpdateStatusScreen extends StatefulWidget {
  final String caseId;

  const UpdateStatusScreen({super.key, required this.caseId});

  @override
  State<UpdateStatusScreen> createState() => _UpdateStatusScreenState();
}

class _UpdateStatusScreenState extends State<UpdateStatusScreen> {
  final _actionNotesCtrl = TextEditingController();
  String? _newStatus;
  bool _loading = false;
  String? _error;
  bool _budgetApprovalConfirmed = false;
  double? _approvedAssistanceAmount;
  final Set<String> _correctionFields = {};
  final Set<String> _correctionDocuments = {};
  String? _rejectionReasonCode;

  List<String> _getValidNextStatuses(String currentStatus) {
    return validNextCaseStatuses(currentStatus);
  }

  String get _notesLabel => switch (_newStatus) {
    statusRejected =>
      _rejectionReasonCode == 'other'
          ? 'Additional explanation *'
          : 'Additional explanation (optional)',
    statusNeedsCorrection => 'Revision instructions *',
    statusProcessing => 'Processing notes *',
    statusApproved => 'Approval notes *',
    statusForClaiming => 'Claiming instructions *',
    statusReleased => 'Release details *',
    _ => 'Status update notes *',
  };

  String get _notesHint => switch (_newStatus) {
    statusRejected =>
      'Add specific details that will help explain the decision',
    statusNeedsCorrection =>
      'Explain what is incorrect and what the resident should revise',
    statusProcessing =>
      'Describe the initial review or processing action completed',
    statusApproved =>
      'Record the basis for approval and any important approval details',
    statusForClaiming =>
      'Provide any instructions or details needed for claiming',
    statusReleased =>
      'Record how, when, or to whom the assistance was released',
    _ => 'Describe the reason and relevant details for this status update',
  };

  String get _missingNotesMessage => switch (_newStatus) {
    statusRejected => 'Please provide the reason for rejection.',
    statusNeedsCorrection => 'Please provide revision instructions.',
    statusProcessing => 'Please provide processing notes.',
    statusApproved => 'Please provide approval notes.',
    statusForClaiming => 'Please provide claiming instructions.',
    statusReleased => 'Please provide release details.',
    _ => 'Please provide notes for this status update.',
  };

  Future<void> _selectStatus(String? status) async {
    if (status != statusNeedsCorrection) {
      _correctionFields.clear();
      _correctionDocuments.clear();
    }
    if (status != statusApproved) {
      setState(() {
        _newStatus = status;
        if (status != statusRejected) _rejectionReasonCode = null;
        _budgetApprovalConfirmed = false;
        _approvedAssistanceAmount = null;
      });
      return;
    }

    final confirmation = await showBudgetApprovalPreviewDialog(
      context,
      caseId: widget.caseId,
    );
    if (!mounted) return;
    setState(() {
      _newStatus = confirmation != null ? statusApproved : null;
      _budgetApprovalConfirmed = confirmation != null;
      _approvedAssistanceAmount = confirmation?.assistanceAmount;
    });
  }

  Future<void> _saveUpdate() async {
    if (_newStatus == null) {
      setState(() => _error = 'Please select a new status.');
      return;
    }
    if (_newStatus == statusRejected && _rejectionReasonCode == null) {
      setState(() => _error = 'Please select a reason for rejection.');
      return;
    }
    if (_newStatus == statusRejected &&
        _rejectionReasonCode == 'other' &&
        _actionNotesCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please explain the other rejection reason.');
      return;
    }
    if (_newStatus != statusRejected && _actionNotesCtrl.text.trim().isEmpty) {
      setState(() => _error = _missingNotesMessage);
      return;
    }
    if (_newStatus == statusNeedsCorrection &&
        _correctionFields.isEmpty &&
        _correctionDocuments.isEmpty) {
      setState(
        () => _error =
            'Select at least one information field or document to correct.',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final auth = context.read<AuthService>();
      final user = auth.currentUserModel;

      // Get current case data
      final caseDoc = await db.collection('cases').doc(widget.caseId).get();
      if (!caseDoc.exists) {
        setState(() {
          _loading = false;
          _error = 'Service request not found.';
        });
        return;
      }
      final caseData = caseDoc.data()!;
      final currentStatus = caseData['status'] ?? '';
      final refNumber = caseData['referenceNumber'] ?? '';
      final rejectionLabel = _newStatus == statusRejected
          ? rejectionReasonLabel(_rejectionReasonCode)
          : null;
      final enteredNotes = _actionNotesCtrl.text.trim();
      final statusNotes = rejectionLabel == null
          ? enteredNotes
          : enteredNotes.isEmpty
          ? rejectionLabel
          : '$rejectionLabel — $enteredNotes';

      // Validate transition
      final valid = _getValidNextStatuses(currentStatus);
      if (!valid.contains(_newStatus)) {
        setState(() {
          _loading = false;
          _error = 'Cannot transition from "$currentStatus" to "$_newStatus".';
        });
        return;
      }

      // Business rule: BASS medical cannot approve without Certificate of Admission
      final serviceCategory = caseData['serviceCategory'] ?? '';
      final serviceSubType = caseData['serviceSubType'] ?? '';
      final caseDocuments = List<Map<String, dynamic>>.from(
        caseData['documents'] ?? const [],
      );
      final protectedRegistryFields = _verifiedRegistryFieldsForCase(caseData);
      final invalidCorrectionFields = _correctionFields.intersection(
        protectedRegistryFields,
      );
      if (_newStatus == statusNeedsCorrection &&
          invalidCorrectionFields.isNotEmpty) {
        setState(() {
          _loading = false;
          _correctionFields.removeAll(invalidCorrectionFields);
          final labels = invalidCorrectionFields.map(_fieldLabel).join(', ');
          _error =
              '$labels came from a verified Citizen Registry record and cannot be corrected from the service request. Use My Record to request a registry correction instead.';
        });
        return;
      }
      final protectedRegistryDocuments = caseDocuments
          .where(
            (document) =>
                document['status'] == 'reused' ||
                document['reusedFromVault'] == true,
          )
          .map((document) => (document['name'] ?? '').toString())
          .where((name) => name.isNotEmpty)
          .toSet();
      final invalidCorrectionDocuments = _correctionDocuments.intersection(
        protectedRegistryDocuments,
      );
      if (_newStatus == statusNeedsCorrection &&
          invalidCorrectionDocuments.isNotEmpty) {
        setState(() {
          _loading = false;
          _correctionDocuments.removeAll(invalidCorrectionDocuments);
          _error =
              'Verified Citizen Registry documents cannot be marked for revision. Request a registry correction if the source document must be reviewed.';
        });
        return;
      }
      final hasMissingRequiredDocuments = caseDocuments.any(
        (document) =>
            document['required'] == true &&
            document['status'] != 'uploaded' &&
            document['status'] != 'reused',
      );
      if (_newStatus == statusRejected && hasMissingRequiredDocuments) {
        setState(() {
          _loading = false;
          _error =
              'Service requests cannot be rejected only because documents are missing. '
              'Choose For Revision and flag the missing documents.';
        });
        return;
      }
      if (_newStatus == 'approved' &&
          serviceCategory == 'bass' &&
          (serviceSubType.toLowerCase().contains('dialysis') ||
              serviceSubType.toLowerCase().contains('chemotherapy') ||
              serviceSubType.toLowerCase().contains('major'))) {
        final documents = List<Map<String, dynamic>>.from(
          caseData['documents'] ?? [],
        );
        final certOfAdmission = documents
            .where(
              (d) =>
                  d['name']!.toLowerCase().contains('certificate of admission'),
            )
            .toList();
        if (certOfAdmission.isEmpty ||
            certOfAdmission.first['status'] != 'uploaded') {
          setState(() {
            _loading = false;
            _error =
                'Cannot approve: Certificate of Admission is required for BASS medical service requests.';
          });
          return;
        }
      }

      // Business rule: VAW/BCPC cannot reject without reason
      if (_newStatus == 'rejected' &&
          (serviceCategory == 'vaw' || statusNotes.length < 10)) {
        if (serviceCategory == 'vaw' && statusNotes.isEmpty) {
          setState(() {
            _loading = false;
            _error =
                'VAW/BCPC service requests require a reason for rejection.';
          });
          return;
        }
      }

      if (_newStatus == statusForClaiming && user?.isCaptain != true) {
        await CaseStatusService(firestore: db).requestForClaimingApproval(
          caseId: widget.caseId,
          notes: statusNotes,
          staffId: user?.uid ?? '',
          staffName: user?.name ?? 'Staff',
          staffRole: user?.effectiveRole ?? '',
          referenceNumber: refNumber,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'For Claiming approval was sent to the Barangay Captain.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          context.go('/dashboard/case/${widget.caseId}');
        }
        return;
      }

      await CaseStatusService(firestore: db).updateStatus(
        caseId: widget.caseId,
        newStatus: _newStatus!,
        notes: statusNotes,
        staffId: user?.uid ?? '',
        staffName: user?.name ?? 'Staff',
        staffRole: user?.effectiveRole ?? '',
        referenceNumber: refNumber,
        budgetApprovalConfirmed: _budgetApprovalConfirmed,
        approvedAssistanceAmount: _approvedAssistanceAmount,
        correctionFields: _correctionFields.toList(),
        correctionDocuments: _correctionDocuments.toList(),
        rejectionReasonCode: _newStatus == statusRejected
            ? _rejectionReasonCode
            : null,
        rejectionReasonLabel: rejectionLabel,
        rejectionReasonDetails: _newStatus == statusRejected
            ? enteredNotes
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status updated successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/dashboard/case/${widget.caseId}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Update failed: $e';
        });
      }
    }
  }

  static String _formatStatus(String status) => caseStatusLabel(status);

  static Set<String> _verifiedRegistryFieldsForCase(Map<String, dynamic> data) {
    final isInfrastructureConcern =
        (data['serviceCategory'] ?? '').toString() == 'community' &&
        (data['serviceSubType'] ?? '').toString() == 'Infrastructure Concern';
    if (isInfrastructureConcern || data['requestedForSelf'] == false) {
      return <String>{};
    }
    final fields = Set<String>.from(
      (data['verifiedRegistryFields'] as List? ?? const []).map(
        (field) => field.toString(),
      ),
    );
    if (data['verifiedRegistryAddressUsed'] == true ||
        data['registryMatchStatus'] == 'verified_match') {
      fields.add('address');
    }
    return fields;
  }

  static String _fieldLabel(String key) => key
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Service request not found.'));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final currentStatus = data['status'] ?? '';
        final isConfidential = data['isConfidential'] ?? false;
        final residentName = isConfidential
            ? 'Confidential'
            : (data['residentName'] ?? '');
        final ref = data['referenceNumber'] ?? '';
        final validNext = _getValidNextStatuses(currentStatus);
        final verifiedRegistryFields = _verifiedRegistryFieldsForCase(data);
        final correctableInformation =
            (data['requestDetails'] as Map? ?? const {}).keys
                .map((key) => key.toString())
                .where(
                  (key) =>
                      key != 'assistanceAmount' &&
                      !verifiedRegistryFields.contains(key),
                )
                .toList();

        // Check for missing docs
        final documents = List<Map<String, dynamic>>.from(
          data['documents'] ?? [],
        );
        final missingDocs = documents
            .where(
              (d) =>
                  d['required'] == true &&
                  d['status'] != 'uploaded' &&
                  d['status'] != 'reused',
            )
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => context.go('/dashboard/case/${widget.caseId}'),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to service request details'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Update Service Request Status',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$ref · $residentName',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Missing docs warning
              if (missingDocs.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This service request has ${missingDocs.length} missing required documents. Proceeding to Released/Approved requires all documents to be validated first.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Status transition
              Row(
                children: [
                  // Current status (read-only)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Status',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              StatusBadge(status: currentStatus),
                              const Spacer(),
                              Text(
                                _formatStatus(currentStatus),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.arrow_forward, color: Colors.grey),
                  const SizedBox(width: 16),
                  // New status dropdown
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New Status',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(_newStatus),
                          initialValue: _newStatus,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          hint: const Text('Select new status'),
                          items: validNext
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(_formatStatus(s)),
                                ),
                              )
                              .toList(),
                          onChanged: _selectStatus,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_newStatus == statusRejected) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Rejected is a final decision. Use For Revision when '
                    'information or documents can still be corrected.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (_newStatus == statusNeedsCorrection) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Flag items the resident must correct *',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'The resident will edit only these items in the same service request.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      if (correctableInformation.isNotEmpty)
                        const Text(
                          'Information',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ...correctableInformation.map(
                        (key) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_fieldLabel(key)),
                          subtitle: Text(
                            (data['requestDetails'][key] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: _correctionFields.contains(key),
                          onChanged: (selected) => setState(() {
                            selected == true
                                ? _correctionFields.add(key)
                                : _correctionFields.remove(key);
                          }),
                        ),
                      ),
                      if (documents.any(
                        (document) => document['status'] == 'uploaded',
                      )) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Documents',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        ...documents
                            .where(
                              (document) =>
                                  document['status'] == 'uploaded' &&
                                  document['reusedFromVault'] != true,
                            )
                            .map((document) {
                              final name = (document['name'] ?? '').toString();
                              return CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(name),
                                subtitle: const Text(
                                  'Replace or correct this uploaded document',
                                ),
                                value: _correctionDocuments.contains(name),
                                onChanged: (selected) => setState(() {
                                  selected == true
                                      ? _correctionDocuments.add(name)
                                      : _correctionDocuments.remove(name);
                                }),
                              );
                            }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (_newStatus == statusRejected) ...[
                const Text(
                  'Reason for rejection *',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _rejectionReasonCode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    hintText: 'Select the primary rejection reason',
                    border: OutlineInputBorder(),
                  ),
                  items: rejectionReasonLabels.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _rejectionReasonCode = value;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
              ],

              Text(
                _notesLabel,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _actionNotesCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: _notesHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // Error
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _saveUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kNavy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save update',
                              style: TextStyle(fontSize: 15),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () =>
                                context.go('/dashboard/case/${widget.caseId}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _actionNotesCtrl.dispose();
    super.dispose();
  }
}
