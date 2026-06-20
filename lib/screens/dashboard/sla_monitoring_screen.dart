import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/sla_bar.dart';
import '../../widgets/status_badge.dart';
import '../../utils/sla_calculator.dart' as sla;

class SlaMonitoringScreen extends StatelessWidget {
  const SlaMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .where('status', whereIn: ['pending_review', 'processing', 'awaiting_docs', 'approved'])
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
          final deadline = data['slaDeadline'] is Timestamp
              ? (data['slaDeadline'] as Timestamp).toDate()
              : null;
          if (deadline == null) continue;

          final status = sla.computeSLAStatus(deadline);
          if (status == 'on_time') onTime++;
          else if (status == 'near_deadline') nearDeadline++;
          else overdue++;

          caseRows.add({
            'id': doc.id,
            'ref': data['referenceNumber'] ?? '',
            'category': data['serviceCategory'] ?? '',
            'name': data['isConfidential'] == true ? 'Confidential' : (data['residentName'] ?? ''),
            'subType': data['serviceSubType'] ?? '',
            'submitted': data['submissionTimestamp'],
            'deadline': deadline,
            'slaStatus': status,
          });
        }

        final total = onTime + nearDeadline + overdue;
        final complianceRate = total > 0 ? (onTime / total * 100).toStringAsFixed(1) : '100.0';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SLA Monitoring',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 4),
              const Text("Active cases monitored against Citizens' Charter deadlines",
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),

              // KPI row
              Row(
                children: [
                  Expanded(child: KpiCard(label: 'On Time', value: '$onTime', accentColor: Colors.green, icon: Icons.check_circle)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Near Deadline', value: '$nearDeadline', accentColor: Colors.orange, icon: Icons.warning)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Overdue', value: '$overdue', accentColor: Colors.red, icon: Icons.error)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Compliance Rate', value: '$complianceRate%', accentColor: Colors.blue, icon: Icons.assessment)),
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
                      const Icon(Icons.warning, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text('$overdue overdue cases require immediate attention.',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

              // Active cases list
              const Text('Active cases — SLA status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 12),
              if (caseRows.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No active cases.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ...caseRows.map((c) {
                  final ts = c['submitted'] is Timestamp ? (c['submitted'] as Timestamp).toDate() : DateTime.now();
                  final dateStr = '${ts.month}/${ts.day}/${ts.year}';
                  final timeStr = sla.timeRemainingString(c['deadline']);

                  return Container(
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
                            Text(c['ref'], style: const TextStyle(fontWeight: FontWeight.bold, color: kNavy, fontSize: 13)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                              child: Text((c['category'] as String).toUpperCase(),
                                  style: const TextStyle(fontSize: 9, color: kNavy, fontWeight: FontWeight.bold)),
                            ),
                            const Spacer(),
                            StatusBadge(status: c['slaStatus']),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${c['name']} · $dateStr', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        const SizedBox(height: 8),
                        SlaBar(slaStatus: c['slaStatus'], timeRemaining: timeStr),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
