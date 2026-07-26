import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../utils/sla_calculator.dart' as sla;
import '../../services/auth_service.dart';
import '../../widgets/status_badge.dart';

class OverdueCasesScreen extends StatefulWidget {
  const OverdueCasesScreen({super.key});

  @override
  State<OverdueCasesScreen> createState() => _OverdueCasesScreenState();
}

class _OverdueCasesScreenState extends State<OverdueCasesScreen> {
  final _notesCtrl = TextEditingController();
  String? _selectedCaseId;
  final _reasons = [
    'Awaiting resident documents',
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
      stream: FirebaseFirestore.instance
          .collection('cases')
          .where(
            'status',
            whereIn: [
              'pending_review',
              'processing',
              'awaiting_docs',
              'approved',
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
          final deadline = data['slaDeadline'] is Timestamp
              ? (data['slaDeadline'] as Timestamp).toDate()
              : null;
          if (deadline == null) continue;
          if (sla.computeSLAStatus(deadline) == 'overdue') {
            overdueCases.add({
              'id': doc.id,
              'ref': data['referenceNumber'] ?? '',
              'category': data['serviceCategory'] ?? '',
              'name': data['isConfidential'] == true
                  ? 'Confidential'
                  : (data['residentName'] ?? ''),
              'deadline': deadline,
              'caseStatus': data['status'] ?? '',
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
                    '${overdueCases.length} cases are overdue. Update their status or add a resolution note to clear the flag.',
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
                  final deadline = c['deadline'] as DateTime;
                  final daysOverdue = DateTime.now()
                      .difference(deadline)
                      .inDays;
                  return InkWell(
                    onTap: () => _showUpdateStatusDialog(c),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                  '+$daysOverdue days overdue',
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Tap to update status',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: Colors.grey.shade400,
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
                  onPressed: _selectedCaseId != null && _selectedReason != null
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
  }

  void _showUpdateStatusDialog(Map<String, dynamic> c) {
    final auth = context.read<AuthService>();
    final currentUser = auth.currentUserModel;
    String? newStatus;
    String? notes;
    String? notesError;

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
                    items: const [
                      DropdownMenuItem(
                        value: 'pending_review',
                        child: Text('Pending Review'),
                      ),
                      DropdownMenuItem(
                        value: 'processing',
                        child: Text('Processing'),
                      ),
                      DropdownMenuItem(
                        value: 'awaiting_docs',
                        child: Text('Awaiting Documents'),
                      ),
                      DropdownMenuItem(
                        value: 'approved',
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem(
                        value: 'released',
                        child: Text('Released'),
                      ),
                      DropdownMenuItem(
                        value: 'rejected',
                        child: Text('Rejected'),
                      ),
                    ],
                    onChanged: (v) => setState(() => newStatus = v),
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
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();
      final caseRef = db.collection('cases').doc(caseId);
      final currentCase = await caseRef.get();
      final previousStatus = currentCase.data()?['status'] ?? '';
      final logRef = caseRef.collection('actionLog').doc();
      final batch = db.batch();

      batch.update(caseRef, {'status': newStatus, 'lastUpdated': now});
      batch.set(logRef, {
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? '',
        'timestamp': now,
        'staffId': user?.uid ?? '',
        'staffName': user?.name ?? 'Unknown',
        'action': 'Status changed: $previousStatus → $newStatus',
        'previousStatus': previousStatus,
        'newStatus': newStatus,
        'notes': notes,
        'smsSent': false,
        'smsBody': '',
      });
      await batch.commit();

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
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(_selectedCaseId)
          .collection('actionLog')
          .add({
            'caseId': _selectedCaseId,
            'referenceNumber': _selectedCaseRef ?? '',
            'timestamp': FieldValue.serverTimestamp(),
            'staffId': '',
            'staffName': 'System',
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
