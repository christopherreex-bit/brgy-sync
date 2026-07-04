import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';
import '../../services/export_service.dart';

class ComplianceReportScreen extends StatefulWidget {
  const ComplianceReportScreen({super.key});

  @override
  State<ComplianceReportScreen> createState() => _ComplianceReportScreenState();
}

class _ComplianceReportScreenState extends State<ComplianceReportScreen> {
  String? _selectedMonth;
  String? _selectedCategory;
  List<Map<String, dynamic>> _breakdownData = [];
  int _totalReceived = 0;
  int _completedOnTime = 0;
  int _overdueCases = 0;

  final _months = const [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  final _categories = const [
    'All Categories',
    'BASS Assistance',
    'Barangay Documents',
    'Community Services',
    'Beneficiary Registration',
    'VAW / BCPC Report',
    'Education Incentive',
    'Ad Hoc / Special Program',
  ];

  DateTimeRange? _getMonthRange() {
    if (_selectedMonth == null) return null;
    final monthIndex = _months.indexOf(_selectedMonth!);
    if (monthIndex == -1) return null;
    final now = DateTime.now();
    final year = now.year;
    return DateTimeRange(
      start: DateTime(year, monthIndex + 1, 1),
      end: DateTime(year, monthIndex + 2, 0, 23, 59, 59),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMonth = _months[DateTime.now().month - 1];
    final month = _selectedMonth ?? currentMonth;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compliance Report',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text("Citizens' Charter compliance summary and breakdown.",
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),

          // Filters
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: month,
                  decoration: const InputDecoration(
                    labelText: 'Reporting Period',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setState(() => _selectedMonth = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCategory ?? 'All Categories',
                  decoration: const InputDecoration(
                    labelText: 'Service Category',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Summary KPIs (from SLA data)
          StreamBuilder<QuerySnapshot>(
            stream: () {
              Query query = FirebaseFirestore.instance
                  .collection('cases')
                  .where('status', whereIn: ['released', 'rejected']);
              final range = _getMonthRange();
              if (range != null) {
                query = query
                    .where('submissionTimestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
                    .where('submissionTimestamp', isLessThanOrEqualTo: Timestamp.fromDate(range.end));
              }
              return query.snapshots();
            }(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              _totalReceived = 0;
              _completedOnTime = 0;
              _overdueCases = 0;

              final categoryBreakdown = <String, Map<String, int>>{};

              for (final doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final cat = data['serviceCategory'] ?? 'unknown';
                final slaStatus = data['slaStatus'] ?? 'on_time';

                // Apply category filter
                if (_selectedCategory != null && _selectedCategory! != 'All Categories' && cat != _selectedCategory) {
                  continue;
                }

                _totalReceived++;
                if (slaStatus == 'on_time') _completedOnTime++;
                if (slaStatus == 'overdue') _overdueCases++;

                categoryBreakdown.putIfAbsent(cat, () => {'total': 0, 'onTime': 0, 'overdue': 0});
                categoryBreakdown[cat]!['total'] = categoryBreakdown[cat]!['total']! + 1;
                if (slaStatus == 'on_time') {
                  categoryBreakdown[cat]!['onTime'] = categoryBreakdown[cat]!['onTime']! + 1;
                }
                if (slaStatus == 'overdue') {
                  categoryBreakdown[cat]!['overdue'] = categoryBreakdown[cat]!['overdue']! + 1;
                }
              }

              // Store breakdown data for export
              _breakdownData = categoryBreakdown.entries.map((e) => {
                'category': e.key,
                'total': e.value['total']!,
                'onTime': e.value['onTime']!,
                'overdue': e.value['overdue']!,
              }).toList();

              final avgTime = _totalReceived > 0 ? '~${(_completedOnTime / _totalReceived * 100).toStringAsFixed(0)}% on-time' : 'N/A';

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: KpiCard(label: 'Total Received', value: '$_totalReceived', icon: Icons.inbox)),
                      const SizedBox(width: 12),
                      Expanded(child: KpiCard(label: 'Completed On Time', value: '$_completedOnTime', accentColor: Colors.green, icon: Icons.check_circle)),
                      const SizedBox(width: 12),
                      Expanded(child: KpiCard(label: 'Overdue Cases', value: '$_overdueCases', accentColor: Colors.red, icon: Icons.error)),
                      const SizedBox(width: 12),
                      Expanded(child: KpiCard(label: 'Avg Processing', value: avgTime, icon: Icons.timer)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Breakdown table
                  const Text('Breakdown by Category',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          ),
                          child: const Row(
                            children: [
                              Expanded(flex: 3, child: Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(child: Text('Received', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(child: Text('On Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(child: Text('Overdue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(child: Text('Rate %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                          ),
                        ),
                        if (categoryBreakdown.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No data available for the selected period.', style: TextStyle(color: Colors.grey)),
                          )
                        else
                          ...categoryBreakdown.entries.map((entry) {
                            final cat = entry.key;
                            final d = entry.value;
                            final rate = d['total']! > 0 ? (d['onTime']! / d['total']! * 100).toStringAsFixed(1) : '0.0';
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(flex: 3, child: Text(cat.toUpperCase(), style: const TextStyle(fontSize: 12))),
                                  Expanded(child: Text('${d['total']}', style: const TextStyle(fontSize: 12))),
                                  Expanded(child: Text('${d['onTime']}', style: const TextStyle(fontSize: 12))),
                                  Expanded(child: Text('${d['overdue']}', style: const TextStyle(fontSize: 12))),
                                  Expanded(child: Text('$rate%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),
          // Export buttons
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportCsv(),
                icon: const Icon(Icons.download),
                label: const Text('Export (.xlsx)'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _exportPdf(),
                icon: const Icon(Icons.print),
                label: const Text('Print PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _exportCsv() {
    if (_breakdownData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to export.')),
      );
      return;
    }
    ExportService.downloadCsv(
      headers: ['Category', 'Received', 'On Time', 'Overdue', 'Rate %'],
      rows: _breakdownData.map<List<String>>((d) {
        final total = d['total'] as int;
        final onTime = d['onTime'] as int;
        final rate = total > 0 ? (onTime / total * 100).toStringAsFixed(1) : '0.0';
        return <String>[
          (d['category'] as String).toUpperCase(),
          '$total',
          '$onTime',
          '${d['overdue']}',
          '$rate%',
        ];
      }).toList(),
      filename: 'compliance_report_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Compliance report exported as CSV.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _exportPdf() {
    if (_breakdownData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to export.')),
      );
      return;
    }
    ExportService.generateCompliancePdf(
      month: _selectedMonth ?? 'Current',
      breakdown: _breakdownData,
      totalReceived: _totalReceived,
      completedOnTime: _completedOnTime,
      overdueCases: _overdueCases,
    );
  }
}
