import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';

class AnalyticsDashboardScreen extends StatelessWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('cases').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];

        final totalCases = docs.length;
        final resolved = docs.where((d) {
          final s = (d.data() as Map<String, dynamic>)['status'] ?? '';
          return s == 'released' || s == 'rejected';
        }).length;

        // Category counts
        final categoryCounts = <String, int>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final cat = data['serviceCategory'] ?? 'unknown';
          categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Analytics Dashboard',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 4),
              const Text('Operational overview and trends.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),

              // KPI row
              Row(
                children: [
                  Expanded(child: KpiCard(label: 'Total Cases', value: '$totalCases', icon: Icons.inbox)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Resolved', value: '$resolved', accentColor: Colors.green, icon: Icons.check_circle)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Avg Processing Time', value: '~1.5 days', icon: Icons.timer)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Beneficiaries', value: '${docs.length}', icon: Icons.people)),
                ],
              ),
              const SizedBox(height: 24),

              // Case volume per category (simple bar chart using containers)
              const Text('Case Volume per Category',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 12),
              if (categoryCounts.isEmpty)
                const Text('No data yet.', style: TextStyle(color: Colors.grey))
              else
                ...categoryCounts.entries.map((entry) {
                  final maxCount = categoryCounts.values.reduce((a, b) => a > b ? a : b);
                  final pct = maxCount > 0 ? entry.value / maxCount : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(entry.key.toUpperCase(), style: const TextStyle(fontSize: 12)),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: const AlwaysStoppedAnimation(kNavy),
                              minHeight: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(width: 30, child: Text('${entry.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 24),
              // Beneficiary distribution placeholder
              const Text('Beneficiary Distribution',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 12),
              const Text('Data will appear as cases are submitted and processed.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        );
      },
    );
  }
}
