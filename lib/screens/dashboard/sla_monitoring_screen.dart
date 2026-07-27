import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/sla_bar.dart';
import '../../widgets/status_badge.dart';
import '../../utils/sla_calculator.dart' as sla;
import '../../services/auth_service.dart';
import '../../services/case_status_service.dart';

class SlaMonitoringScreen extends StatefulWidget {
  const SlaMonitoringScreen({super.key});

  @override
  State<SlaMonitoringScreen> createState() => _SlaMonitoringScreenState();
}

class _SlaMonitoringScreenState extends State<SlaMonitoringScreen> {
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
                    '${c['name']} · ${c['subType']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: newStatus,
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
      await CaseStatusService().updateStatus(
        caseId: caseId,
        newStatus: newStatus,
        notes: notes,
        staffId: user?.uid ?? '',
        staffName: user?.name ?? 'Unknown',
        referenceNumber: referenceNumber,
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
            int onTime = 0, nearDeadline = 0, overdue = 0;
            final caseRows = <Map<String, dynamic>>[];

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

              final status = sla.computeSLAStatus(deadline);
              if (status == 'on_time') {
                onTime++;
              } else if (status == 'near_deadline') {
                nearDeadline++;
              } else {
                overdue++;
              }

              caseRows.add({
                'id': doc.id,
                'ref': data['referenceNumber'] ?? '',
                'category': data['serviceCategory'] ?? '',
                'name': data['isConfidential'] == true
                    ? 'Confidential'
                    : (data['residentName'] ?? ''),
                'subType': data['serviceSubType'] ?? '',
                'submitted': data['submissionTimestamp'],
                'deadline': deadline,
                'slaStatus': status,
                'caseStatus': data['status'] ?? '',
              });
            }

            final total = onTime + nearDeadline + overdue;
            final complianceRate = total > 0
                ? (onTime / total * 100).toStringAsFixed(1)
                : '100.0';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SLA Monitoring',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Active cases monitored against Citizens' Charter deadlines",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // KPI row
                  Row(
                    children: [
                      Expanded(
                        child: KpiCard(
                          label: 'On Time',
                          value: '$onTime',
                          accentColor: Colors.green,
                          icon: Icons.check_circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          label: 'Near Deadline',
                          value: '$nearDeadline',
                          accentColor: Colors.orange,
                          icon: Icons.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          label: 'Overdue',
                          value: '$overdue',
                          accentColor: Colors.red,
                          icon: Icons.error,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          label: 'Compliance Rate',
                          value: '$complianceRate%',
                          accentColor: Colors.blue,
                          icon: Icons.assessment,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Alert banner
                  if (overdue > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$overdue overdue cases require immediate attention.',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Active cases list
                  const Text(
                    'Active cases — SLA status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (caseRows.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No active cases.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...caseRows.map((c) {
                      final ts = c['submitted'] is Timestamp
                          ? (c['submitted'] as Timestamp).toDate()
                          : DateTime.now();
                      final dateStr = '${ts.month}/${ts.day}/${ts.year}';
                      final timeStr = sla.timeRemainingString(c['deadline']);

                      return InkWell(
                        onTap: () => _showUpdateStatusDialog(c),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kNavy.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      (c['category'] as String).toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: kNavy,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (c['caseStatus'] == 'processing'
                                                  ? Colors.blue
                                                  : Colors.orange)
                                              .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      (c['caseStatus'] as String).replaceAll(
                                        '_',
                                        ' ',
                                      ),
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: c['caseStatus'] == 'processing'
                                            ? Colors.blue
                                            : Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  StatusBadge(status: c['slaStatus']),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${c['name']} · $dateStr',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SlaBar(
                                slaStatus: c['slaStatus'],
                                timeRemaining: timeStr,
                                submittedAt: ts,
                                deadline: c['deadline'] as DateTime,
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
                ],
              ),
            );
          },
        );
      },
    );
  }
}
