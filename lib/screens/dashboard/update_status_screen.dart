import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/case_status_service.dart';
import '../../services/twilio_service.dart';
import '../../widgets/budget_approval_preview_dialog.dart';
import '../../utils/constants.dart';
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

  final _twilio = TwilioService();

  List<String> _getValidNextStatuses(String currentStatus) {
    return validNextCaseStatuses(currentStatus);
  }

  Future<void> _selectStatus(String? status) async {
    if (status != statusApproved) {
      setState(() {
        _newStatus = status;
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

  String _buildSmsPreview(
    String currentStatus,
    String? nextStatus,
    String refNumber,
    String residentMobile,
  ) {
    switch (nextStatus) {
      case 'processing':
        return 'BrgySync: Your case $refNumber is now being processed. Thank you for your patience.';
      case 'awaiting_docs':
        return 'BrgySync: Your case $refNumber requires additional documents. Please submit the missing items to the barangay hall.';
      case 'approved':
        return 'BrgySync: Your case $refNumber has been approved. We will notify you when it is ready for release.';
      case 'for_claiming':
        return 'BrgySync: Your case $refNumber is ready for claiming. Please proceed to the barangay hall.';
      case 'released':
        return 'BrgySync: Your case $refNumber has been released successfully.';
      case 'rejected':
        return 'BrgySync: Your case $refNumber has been reviewed and could not be approved. Please visit the barangay hall for details.';
      default:
        return 'BrgySync: Update on your case $refNumber.';
    }
  }

  Future<void> _saveUpdate() async {
    if (_newStatus == null) {
      setState(() => _error = 'Please select a new status.');
      return;
    }
    if (_actionNotesCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please describe the action taken.');
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
          _error = 'Case not found.';
        });
        return;
      }
      final caseData = caseDoc.data()!;
      final currentStatus = caseData['status'] ?? '';
      final refNumber = caseData['referenceNumber'] ?? '';
      final residentMobile = caseData['residentMobile'] ?? '';

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
                'Cannot approve: Certificate of Admission is required for BASS medical cases.';
          });
          return;
        }
      }

      // Business rule: VAW/BCPC cannot reject without reason
      if (_newStatus == 'rejected' &&
          (serviceCategory == 'vaw' ||
              _actionNotesCtrl.text.trim().length < 10)) {
        if (serviceCategory == 'vaw' && _actionNotesCtrl.text.trim().isEmpty) {
          setState(() {
            _loading = false;
            _error = 'VAW/BCPC cases require a reason for rejection.';
          });
          return;
        }
      }

      if (_newStatus == statusForClaiming && user?.role != roleCaptain) {
        await CaseStatusService(firestore: db).requestForClaimingApproval(
          caseId: widget.caseId,
          notes: _actionNotesCtrl.text.trim(),
          staffId: user?.uid ?? '',
          staffName: user?.name ?? 'Staff',
          staffRole: user?.role ?? '',
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

      // Send SMS — seed data goes to fallback, real residents get actual number
      String? smsError;
      final smsTo = (caseData['isSeedData'] == true)
          ? TwilioService.fallbackNumber
          : (residentMobile.isNotEmpty
                ? residentMobile
                : TwilioService.fallbackNumber);
      switch (_newStatus) {
        case 'processing':
          smsError = await _twilio.sendStatusProcessing(smsTo, refNumber);
          break;
        case 'awaiting_docs':
          smsError = await _twilio.sendStatusAwaitingDocs(smsTo, refNumber);
          break;
        case 'approved':
          smsError = await _twilio.sendStatusApproved(smsTo, refNumber);
          break;
        case 'for_claiming':
          smsError = await _twilio.sendStatusForClaiming(smsTo, refNumber);
          break;
        case 'released':
          smsError = await _twilio.sendStatusReleased(smsTo, refNumber);
          break;
        case 'rejected':
          smsError = await _twilio.sendStatusRejected(smsTo, refNumber);
          break;
      }

      await CaseStatusService(firestore: db).updateStatus(
        caseId: widget.caseId,
        newStatus: _newStatus!,
        notes: _actionNotesCtrl.text.trim(),
        staffId: user?.uid ?? '',
        staffName: user?.name ?? 'Staff',
        staffRole: user?.role ?? '',
        referenceNumber: refNumber,
        smsSent: smsError == null,
        smsError: smsError,
        smsBody: _buildSmsPreview(
          currentStatus,
          _newStatus,
          refNumber,
          residentMobile,
        ),
        budgetApprovalConfirmed: _budgetApprovalConfirmed,
        approvedAssistanceAmount: _approvedAssistanceAmount,
      );

      if (mounted) {
        final smsSuccess = smsError == null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              smsSuccess
                  ? 'Status updated and SMS sent successfully.'
                  : 'Status updated. SMS not sent: $smsError',
            ),
            backgroundColor: smsSuccess ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 5),
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

  static String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

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
          return const Center(child: Text('Case not found.'));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final currentStatus = data['status'] ?? '';
        final isConfidential = data['isConfidential'] ?? false;
        final residentName = isConfidential
            ? 'Confidential'
            : (data['residentName'] ?? '');
        final ref = data['referenceNumber'] ?? '';
        final residentMobile = data['residentMobile'] ?? '';
        final validNext = _getValidNextStatuses(currentStatus);

        // Check for missing docs
        final documents = List<Map<String, dynamic>>.from(
          data['documents'] ?? [],
        );
        final missingDocs = documents
            .where((d) => d['required'] == true && d['status'] != 'uploaded')
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => context.go('/dashboard/case/${widget.caseId}'),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to case detail'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Update Case Status',
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
                          'This case has ${missingDocs.length} missing required documents. Proceeding to Released/Approved requires all documents to be validated first.',
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
                          value: _newStatus,
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

              // Action taken
              const Text(
                'Action Taken *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _actionNotesCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText:
                      'Describe what was done, reviewed, or decided on this case',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // SMS preview
              if (_newStatus != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.sms, color: Colors.blue, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'SMS notification to resident',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'An automated SMS will be sent to +639397193163 upon saving this update.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _buildSmsPreview(
                            currentStatus,
                            _newStatus,
                            ref,
                            residentMobile,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

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
                              'Save update & send SMS',
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
