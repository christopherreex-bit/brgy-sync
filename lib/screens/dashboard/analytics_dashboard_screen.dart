import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../utils/constants.dart';
import '../../utils/rejection_reasons.dart';
import '../../widgets/kpi_card.dart';

double calculateCategoryShare(int categoryCount, int totalCases) {
  if (totalCases <= 0) return 0;
  return (categoryCount / totalCases).clamp(0.0, 1.0);
}

class AnalyticsDashboardScreen extends StatelessWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('cases').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load analytics data: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];

        final totalCases = docs.length;
        final released = docs.where((d) {
          final s = (d.data() as Map<String, dynamic>)['status'] ?? '';
          return s == 'released';
        }).length;
        final processingDurations = <Duration>[];
        var beneficiaries = 0;

        // Category counts
        final categoryCounts = <String, int>{};
        final rejectionCounts = <String, int>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final cat = (data['serviceCategory'] ?? 'unknown').toString();
          categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;

          final status = (data['status'] ?? '').toString();
          if (status == statusRejected) {
            final code = (data['rejectionReasonCode'] ?? 'legacy_unspecified')
                .toString();
            rejectionCounts[code] = (rejectionCounts[code] ?? 0) + 1;
          }
          if (status == 'released' && _isBeneficiaryCase(data)) {
            beneficiaries++;
          }

          if (status == 'released' || status == 'rejected') {
            final submittedAt = _timestampDate(data['submissionTimestamp']);
            final completedAt = _timestampDate(data['lastUpdated']);
            if (submittedAt != null &&
                completedAt != null &&
                !completedAt.isBefore(submittedAt)) {
              processingDurations.add(completedAt.difference(submittedAt));
            }
          }
        }
        final averageProcessingTime = _averageDuration(processingDurations);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collectionGroup('actionLog')
              .snapshots(),
          builder: (context, activitySnapshot) {
            final staffActivity = _staffActivity(
              activitySnapshot.data?.docs ?? const [],
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Analytics Dashboard',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Operational overview and trends.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // KPI row
                  Row(
                    children: [
                      Expanded(
                        child: KpiCard(
                          label: 'Total Service Requests',
                          value: '$totalCases',
                          icon: Icons.inbox,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          label: 'Released',
                          value: '$released',
                          accentColor: Colors.green,
                          icon: Icons.check_circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          label: 'Avg Processing Time',
                          value: averageProcessingTime,
                          icon: Icons.timer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          label: 'Beneficiaries',
                          value: '$beneficiaries',
                          icon: Icons.people,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Case volume per category (simple bar chart using containers)
                  const Text(
                    'Service Request Volume per Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (categoryCounts.isEmpty)
                    const Text(
                      'No data yet.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ...categoryCounts.entries.map((entry) {
                      final pct = calculateCategoryShare(
                        entry.value,
                        totalCases,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(
                                entry.key.toUpperCase(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: const AlwaysStoppedAnimation(
                                    kNavy,
                                  ),
                                  minHeight: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 30,
                              child: Text(
                                '${entry.value}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  const Text(
                    'Rejection Reasons',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Primary reasons recorded for rejected service requests.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (rejectionCounts.isEmpty)
                    const Text(
                      'No rejected service requests yet.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ..._rejectionReasonRows(rejectionCounts),

                  const SizedBox(height: 24),
                  const Text(
                    'Staff and Officer Workflow Activity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Counts status decisions recorded in the audit log. These figures describe workload and should not be treated as performance scores by themselves.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (activitySnapshot.hasError)
                    Text(
                      'Could not load employee activity: ${activitySnapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    )
                  else if (!activitySnapshot.hasData)
                    const LinearProgressIndicator()
                  else if (staffActivity.isEmpty)
                    const Text(
                      'No status-change activity has been recorded yet.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    _buildStaffActivityTable(staffActivity),

                  const SizedBox(height: 24),
                  // Beneficiary distribution donut chart
                  const Text(
                    'Beneficiary Distribution',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDonutChart(docs),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Map<String, Map<String, dynamic>> _staffActivity(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> logs,
  ) {
    const countedStatuses = {
      statusProcessing,
      statusNeedsCorrection,
      statusApproved,
      statusForClaiming,
      statusReleased,
      statusRejected,
    };
    final result = <String, Map<String, dynamic>>{};
    for (final document in logs) {
      final data = document.data();
      final status = (data['newStatus'] ?? '').toString();
      if (!countedStatuses.contains(status)) continue;
      final staffId = (data['staffId'] ?? '').toString().trim();
      final staffName = (data['staffName'] ?? 'Unknown employee')
          .toString()
          .trim();
      final key = staffId.isNotEmpty ? staffId : staffName.toLowerCase();
      final row = result.putIfAbsent(key, () {
        return <String, dynamic>{
          'name': staffName.isEmpty ? 'Unknown employee' : staffName,
          'role': (data['staffRole'] ?? '').toString(),
          for (final item in countedStatuses) item: 0,
        };
      });
      row[status] = ((row[status] as int?) ?? 0) + 1;
      if ((row['role'] ?? '').toString().isEmpty) {
        row['role'] = (data['staffRole'] ?? '').toString();
      }
    }
    return result;
  }

  Widget _buildStaffActivityTable(Map<String, Map<String, dynamic>> activity) {
    final rows = activity.values.toList()
      ..sort((a, b) {
        int total(Map<String, dynamic> row) =>
            (row[statusProcessing] as int? ?? 0) +
            (row[statusNeedsCorrection] as int? ?? 0) +
            (row[statusApproved] as int? ?? 0) +
            (row[statusForClaiming] as int? ?? 0) +
            (row[statusReleased] as int? ?? 0) +
            (row[statusRejected] as int? ?? 0);
        return total(b).compareTo(total(a));
      });
    int count(Map<String, dynamic> row, String status) =>
        row[status] as int? ?? 0;
    int total(Map<String, dynamic> row) =>
        count(row, statusProcessing) +
        count(row, statusNeedsCorrection) +
        count(row, statusApproved) +
        count(row, statusForClaiming) +
        count(row, statusReleased) +
        count(row, statusRejected);

    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Employee')),
            DataColumn(label: Text('Processing'), numeric: true),
            DataColumn(label: Text('For Revision'), numeric: true),
            DataColumn(label: Text('Approved'), numeric: true),
            DataColumn(label: Text('For Claiming'), numeric: true),
            DataColumn(label: Text('Released'), numeric: true),
            DataColumn(label: Text('Rejected'), numeric: true),
            DataColumn(label: Text('Total Actions'), numeric: true),
          ],
          rows: rows.map((row) {
            final role = (row['role'] ?? '').toString();
            return DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (role.isNotEmpty)
                        Text(
                          role.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                DataCell(Text('${count(row, statusProcessing)}')),
                DataCell(Text('${count(row, statusNeedsCorrection)}')),
                DataCell(Text('${count(row, statusApproved)}')),
                DataCell(Text('${count(row, statusForClaiming)}')),
                DataCell(Text('${count(row, statusReleased)}')),
                DataCell(Text('${count(row, statusRejected)}')),
                DataCell(Text('${total(row)}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  List<Widget> _rejectionReasonRows(Map<String, int> counts) {
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((entry) {
      final label = entry.key == 'legacy_unspecified'
          ? 'Unspecified legacy reason'
          : rejectionReasonLabel(entry.key);
      final share = total == 0 ? 0.0 : entry.value / total;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 240,
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
                  minHeight: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text(
                '${entry.value}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildDonutChart(List<QueryDocumentSnapshot> docs) {
    // Count beneficiaries by category from released cases
    final counts = <String, int>{
      'BASS Assistance': 0,
      'Birthday Distribution': 0,
      'Education Incentive': 0,
    };

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? '';
      if (status != 'released' || !_isBeneficiaryCase(data)) continue;
      final cat = (data['serviceCategory'] ?? '').toString().toLowerCase();
      switch (cat) {
        case 'bass':
          counts['BASS Assistance'] = counts['BASS Assistance']! + 1;
          break;
        case 'beneficiary':
          counts['Birthday Distribution'] =
              counts['Birthday Distribution']! + 1;
          break;
        case 'education':
          counts['Education Incentive'] = counts['Education Incentive']! + 1;
      }
    }

    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return const Text(
        'No released beneficiary service requests yet.',
        style: TextStyle(color: Colors.grey, fontSize: 13),
      );
    }

    final colors = [
      const Color(0xFF0F2044), // navy — BASS
      const Color(0xFF4A90D9), // blue — Birthday
      const Color(0xFF27AE60), // green — Education
    ];

    final sections = <PieChartSectionData>[];
    final countEntries = counts.entries.toList();
    for (var index = 0; index < countEntries.length; index++) {
      final entry = countEntries[index];
      if (entry.value == 0) continue;
      final pct = entry.value / total * 100;
      sections.add(
        PieChartSectionData(
          value: entry.value.toDouble(),
          title: '${pct.toStringAsFixed(0)}%',
          radius: 50,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          color: colors[index],
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 35,
              sectionsSpace: 2,
            ),
          ),
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
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors[idx],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              Text(
                'Total: $total beneficiaries',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static DateTime? _timestampDate(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
  }

  static bool _isBeneficiaryCase(Map<String, dynamic> data) {
    final category = (data['serviceCategory'] ?? '').toString().toLowerCase();
    return category == 'bass' ||
        category == 'beneficiary' ||
        category == 'education';
  }

  static String _averageDuration(List<Duration> durations) {
    if (durations.isEmpty) return 'N/A';
    final totalMilliseconds = durations.fold<int>(
      0,
      (total, duration) => total + duration.inMilliseconds,
    );
    final average = Duration(
      milliseconds: totalMilliseconds ~/ durations.length,
    );
    final days = average.inDays;
    final hours = average.inHours.remainder(24);
    if (days > 0) {
      final dayLabel = days == 1 ? 'day' : 'days';
      final hourLabel = hours == 1 ? 'hour' : 'hours';
      return hours == 0
          ? '$days $dayLabel'
          : '$days $dayLabel $hours $hourLabel';
    }
    final minutes = average.inMinutes.remainder(60);
    if (average.inHours > 0) {
      final hourLabel = average.inHours == 1 ? 'hour' : 'hours';
      final minuteLabel = minutes == 1 ? 'minute' : 'minutes';
      return minutes == 0
          ? '${average.inHours} $hourLabel'
          : '${average.inHours} $hourLabel $minutes $minuteLabel';
    }
    final minuteLabel = average.inMinutes == 1 ? 'minute' : 'minutes';
    return '${average.inMinutes} $minuteLabel';
  }
}
