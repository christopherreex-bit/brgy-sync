import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../utils/sla_calculator.dart' as sla;
import '../../services/auth_service.dart';
import '../../services/case_status_service.dart';
import '../../widgets/sla_bar.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/budget_approval_preview_dialog.dart';

class OverdueCasesScreen extends StatefulWidget {
  const OverdueCasesScreen({super.key});

  @override
  State<OverdueCasesScreen> createState() => _OverdueCasesScreenState();
}

class _OverdueCasesScreenState extends State<OverdueCasesScreen> {
  final _notesCtrl = TextEditingController();
  String? _selectedCaseId;
  final _reasons = [
    'Budget constraints',
    'Pending barangay captain approval',
    'External agency coordination',
    'Other',
  ];
  String? _selectedReason;
  String? _selectedCaseRef;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('slaConfig').snapshots(),
      builder: (context, configSnapshot) {
        final config = sla.buildSlaConfig(
          (configSnapshot.data?.docs ?? []).map(
            (doc) => doc.data() as Map<String, dynamic>,
          ),
        );
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('cases')
              .where(
                'status',
                whereIn: [
                  'pending_review',
                  'pending',
                  'processing',
                  'awaiting_docs',
                  'approved',
                  'for_claiming',
                ],
              )
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            final overdueCases = <Map<String, dynamic>>[];

            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final submitted = data['submissionTimestamp'] is Timestamp
                  ? (data['submissionTimestamp'] as Timestamp).toDate()
                  : null;
              if (submitted == null) continue;
              final deadline = sla.computeDeadline(
                submitted,
                data['serviceCategory'] ?? '',
                data['serviceSubType'] ?? '',
                config: config,
              );
              if (sla.computeSLAStatus(deadline) == 'overdue') {
                overdueCases.add({
                  'id': doc.id,
                  'ref': data['referenceNumber'] ?? '',
                  'category': data['serviceCategory'] ?? '',
                  'name': data['isConfidential'] == true
                      ? 'Confidential'
                      : (data['residentName'] ?? ''),
                  'submitted': submitted,
                  'deadline': deadline,
                  'caseStatus': normalizeCaseStatus(
                    (data['status'] ?? statusPendingReview).toString(),
                  ),
                });
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Overdue Cases',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cases that have exceeded their SLA deadline.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  if (overdueCases.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        '${overdueCases.length} cases are overdue. Update their '
                        'status or add a resolution note to document the delay.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),

                  // Overdue list
                  if (overdueCases.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No overdue cases. Great job!',
                          style: TextStyle(color: Colors.green, fontSize: 16),
                        ),
                      ),
                    )
                  else
                    ...overdueCases.map((c) {
                      final submitted = c['submitted'] as DateTime;
                      final deadline = c['deadline'] as DateTime;
                      final overdueDuration = sla.timeRemainingString(deadline);
                      return InkWell(
                        onTap: () => context.push('/dashboard/case/${c['id']}'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.red.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              c['ref'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: kNavy,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            StatusBadge(
                                              status: c['caseStatus'] as String,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${c['name']} · Deadline: ${deadline.month}/${deadline.day}/${deadline.year}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      overdueDuration,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SlaBar(
                                slaStatus: slaOverdue,
                                timeRemaining: overdueDuration,
                                submittedAt: submitted,
                                deadline: deadline,
                              ),
                              const SizedBox(height: 8),
                              _LatestResolutionNote(caseId: c['id'] as String),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => context.push(
                                      '/dashboard/case/${c['id']}',
                                    ),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('View case'),
                                  ),
                                  const Spacer(),
                                  OutlinedButton.icon(
                                    onPressed: () => _showUpdateStatusDialog(c),
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Update status'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 32),
                  // Resolution note form
                  const Text(
                    'Add Resolution Note',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedCaseId,
                    decoration: const InputDecoration(
                      labelText: 'Case Reference',
                      border: OutlineInputBorder(),
                    ),
                    items: overdueCases
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text('${c['ref']} - ${c['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      final found = overdueCases
                          .cast<Map<String, dynamic>>()
                          .firstWhere(
                            (c) => c['id'] == v,
                            orElse: () => <String, dynamic>{'ref': ''},
                          );
                      setState(() {
                        _selectedCaseId = v;
                        _selectedCaseRef = found['ref'] as String?;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedReason,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Delay',
                      border: OutlineInputBorder(),
                    ),
                    items: _reasons
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedReason = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Additional Notes',
                      hintText:
                          'Describe corrective action taken or reason for delay',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed:
                          _selectedCaseId != null && _selectedReason != null
                          ? _saveNote
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kNavy,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save exception note'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showUpdateStatusDialog(Map<String, dynamic> c) {
    final auth = context.read<AuthService>();
    final currentUser = auth.currentUserModel;
    String? newStatus;
    String? notes;
    String? notesError;
    bool budgetApprovalConfirmed = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text('Update Status: ${c['ref']}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${c['name']} · Overdue',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: newStatus,
                    decoration: const InputDecoration(
                      labelText: 'New Status',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        validNextCaseStatuses(
                              (c['caseStatus'] ?? '').toString(),
                            )
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(caseStatusLabel(status)),
                              ),
                            )
                            .toList(),
                    onChanged: (value) async {
                      if (value != statusApproved) {
                        setState(() {
                          newStatus = value;
                          budgetApprovalConfirmed = false;
                        });
                        return;
                      }
                      final confirmed = await showBudgetApprovalPreviewDialog(
                        dialogCtx,
                        caseId: c['id'] as String,
                      );
                      setState(() {
                        newStatus = confirmed ? statusApproved : null;
                        budgetApprovalConfirmed = confirmed;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) {
                      notes = value;
                      if (value.trim().isNotEmpty && notesError != null) {
                        setState(() => notesError = null);
                      }
                    },
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Reason *',
                      hintText: 'Reason for status change...',
                      border: const OutlineInputBorder(),
                      errorText: notesError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: newStatus == null
                      ? null
                      : () async {
                          final reason = notes?.trim() ?? '';
                          if (reason.isEmpty) {
                            setState(
                              () => notesError =
                                  'Please enter a reason for the status change.',
                            );
                            return;
                          }
                          Navigator.pop(dialogCtx);
                          await _updateCaseStatus(
                            c['id'],
                            newStatus!,
                            reason,
                            currentUser,
                            referenceNumber: c['ref'],
                            budgetApprovalConfirmed: budgetApprovalConfirmed,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateCaseStatus(
    String caseId,
    String newStatus,
    String notes,
    user, {
    String? referenceNumber,
    bool budgetApprovalConfirmed = false,
  }) async {
    try {
      await CaseStatusService().updateStatus(
        caseId: caseId,
        newStatus: newStatus,
        notes: notes,
        staffId: user?.uid ?? '',
        staffName: user?.name ?? 'Unknown',
        referenceNumber: referenceNumber,
        budgetApprovalConfirmed: budgetApprovalConfirmed,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status updated.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveNote() async {
    if (_selectedCaseId == null || _selectedReason == null) return;
    try {
      final currentUser = context.read<AuthService>().currentUserModel;
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(_selectedCaseId)
          .collection('actionLog')
          .add({
            'caseId': _selectedCaseId,
            'referenceNumber': _selectedCaseRef ?? '',
            'timestamp': FieldValue.serverTimestamp(),
            'staffId': currentUser?.uid ?? '',
            'staffName': currentUser?.name ?? 'Unknown',
            'action': 'Resolution note: $_selectedReason',
            'previousStatus': '',
            'newStatus': '',
            'notes': _notesCtrl.text.trim(),
            'smsSent': false,
            'smsBody': '',
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resolution note saved.'),
            backgroundColor: Colors.green,
          ),
        );
        _notesCtrl.clear();
        setState(() {
          _selectedCaseId = null;
          _selectedCaseRef = null;
          _selectedReason = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }
}

class _LatestResolutionNote extends StatelessWidget {
  final String caseId;

  const _LatestResolutionNote({required this.caseId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('actionLog')
          .snapshots(),
      builder: (context, snapshot) {
        final notes =
            [...?snapshot.data?.docs].where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return (data['action'] ?? '').toString().startsWith(
                'Resolution note:',
              );
            }).toList()..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['timestamp'] as Timestamp?;
              final bTime = bData['timestamp'] as Timestamp?;
              return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
                aTime?.millisecondsSinceEpoch ?? 0,
              );
            });
        if (notes.isEmpty) return const SizedBox.shrink();

        final data = notes.first.data() as Map<String, dynamic>;
        final action = (data['action'] ?? '').toString();
        final reason = action.replaceFirst('Resolution note:', '').trim();
        final details = (data['notes'] ?? '').toString().trim();
        final staffName = (data['staffName'] ?? '').toString();
        final timestamp = data['timestamp'] is Timestamp
            ? (data['timestamp'] as Timestamp).toDate()
            : null;
        final dateText = timestamp == null
            ? ''
            : '${timestamp.month}/${timestamp.day}/${timestamp.year} '
                  '${timestamp.hour.toString().padLeft(2, '0')}:'
                  '${timestamp.minute.toString().padLeft(2, '0')}';

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border.all(color: Colors.amber.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.sticky_note_2_outlined,
                    size: 16,
                    color: Colors.amber.shade900,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Latest resolution note: $reason',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(details, style: const TextStyle(fontSize: 12)),
              ],
              if (staffName.isNotEmpty || dateText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    staffName,
                    dateText,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
