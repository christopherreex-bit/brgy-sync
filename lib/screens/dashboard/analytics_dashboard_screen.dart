import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
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
              // Beneficiary distribution donut chart
              const Text('Beneficiary Distribution',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 12),
              _buildDonutChart(docs),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDonutChart(List<QueryDocumentSnapshot> docs) {
    // Count beneficiaries by category from released cases
    final counts = <String, int>{
      'BASS Assistance': 0,
      'Birthday Distribution': 0,
      'Education Incentive': 0,
      'Documents': 0,
      'Other': 0,
    };

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? '';
      if (status != 'released') continue;
      final cat = (data['serviceCategory'] ?? '').toString();
      final subType = (data['serviceSubType'] ?? '').toString();
      switch (cat) {
        case 'bass':
          counts['BASS Assistance'] = counts['BASS Assistance']! + 1;
          break;
        case 'beneficiary':
          if (subType.toLowerCase().contains('senior') || subType.toLowerCase().contains('pwd')) {
            counts['Birthday Distribution'] = counts['Birthday Distribution']! + 1;
          } else {
            counts['Other'] = counts['Other']! + 1;
          }
          break;
        case 'education':
          counts['Education Incentive'] = counts['Education Incentive']! + 1;
          break;
        case 'documents':
          counts['Documents'] = counts['Documents']! + 1;
          break;
        default:
          counts['Other'] = counts['Other']! + 1;
      }
    }

    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return const Text('No resolved cases yet. Data will appear as cases are processed.',
          style: TextStyle(color: Colors.grey, fontSize: 13));
    }

    final colors = [
      const Color(0xFF0F2044), // navy — BASS
      const Color(0xFF4A90D9), // blue — Birthday
      const Color(0xFF27AE60), // green — Education
      const Color(0xFFF39C12), // orange — Documents
      const Color(0xFF95A5A6), // gray — Other
    ];

    final sections = <PieChartSectionData>[];
    var colorIdx = 0;
    for (final entry in counts.entries) {
      if (entry.value == 0) continue;
      final pct = entry.value / total * 100;
      sections.add(PieChartSectionData(
        value: entry.value.toDouble(),
        title: '${pct.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        color: colors[colorIdx % colors.length],
      ));
      colorIdx++;
    }

    return Row(
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: PieChart(PieChartData(
            sections: sections,
            centerSpaceRadius: 35,
            sectionsSpace: 2,
          )),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...counts.entries.where((e) => e.value > 0).map((entry) {
                final idx = counts.keys.toList().indexOf(entry.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[idx], borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 12))),
                      Text('${entry.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              Text('Total: $total beneficiaries', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}
