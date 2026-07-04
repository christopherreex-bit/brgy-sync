import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status_badge.dart';

class ProgramDetailScreen extends StatelessWidget {
  final String programId;

  const ProgramDetailScreen({super.key, required this.programId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('budgetPrograms').doc(programId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Program not found.'));
        }

        final d = snapshot.data!.data() as Map<String, dynamic>;
        final name = d['name'] ?? '';
        final status = d['status'] ?? 'healthy';
        final allocated = (d['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (d['utilized'] as num?)?.toDouble() ?? 0;
        final remaining = allocated - utilized;
        final threshold = (d['thresholdPercent'] as num?)?.toDouble() ?? 10;
        final thresholdAmount = allocated * threshold / 100;
        final isBelowThreshold = remaining <= thresholdAmount;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => context.go('/dashboard/budget'),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Budget Overview'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kNavy)),
                  const SizedBox(width: 12),
                  StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 16),

              if (isBelowThreshold)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Remaining balance has fallen below the ${threshold.toStringAsFixed(0)}% low-budget threshold.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),

              // KPI row
              Row(
                children: [
                  Expanded(child: KpiCard(label: 'Allocated', value: '₱${allocated.toStringAsFixed(0)}')),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Utilized', value: '₱${utilized.toStringAsFixed(0)}', accentColor: status == 'critical' ? Colors.red : Colors.orange)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Remaining', value: '₱${remaining.toStringAsFixed(0)}', accentColor: status == 'critical' ? Colors.red : Colors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Threshold', value: '₱${thresholdAmount.toStringAsFixed(0)}')),
                ],
              ),
              const SizedBox(height: 20),

              // Recent releases
              const Text('Recent Releases',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 4),
              const Text('Auto-deducted on approval', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('budgetTransactions')
                    .where('programId', isEqualTo: programId)
                    .orderBy('timestamp', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, txSnapshot) {
                  final txDocs = txSnapshot.data?.docs ?? [];
                  if (txDocs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No transactions yet.', style: TextStyle(color: Colors.grey)),
                      ),
                    );
                  }
                  return Column(
                    children: txDocs.map((tx) {
                      final t = tx.data() as Map<String, dynamic>;
                      final amount = (t['amount'] as num?)?.toDouble() ?? 0;
                      final ts = t['timestamp'] is Timestamp ? (t['timestamp'] as Timestamp).toDate() : DateTime.now();
                      final dateStr = '${ts.month}/${ts.day}/${ts.year}';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Case Number: ${t['caseId'] ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                ],
                              ),
                            ),
                            Text('-₱${amount.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
