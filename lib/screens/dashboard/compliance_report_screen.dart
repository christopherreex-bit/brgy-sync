import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../utils/sla_calculator.dart' as sla;
import '../../widgets/kpi_card.dart';
import '../../services/export_service.dart';

class ComplianceReportScreen extends StatefulWidget {
  const ComplianceReportScreen({super.key});

  @override
  State<ComplianceReportScreen> createState() => _ComplianceReportScreenState();
}

class _ComplianceReportScreenState extends State<ComplianceReportScreen> {
  late final Stream<QuerySnapshot> _casesStream;
  late final Stream<QuerySnapshot> _slaConfigStream;
  String? _selectedMonth;
  int? _selectedYear;
  String? _selectedCategory;
  List<Map<String, dynamic>> _breakdownData = [];
  int _totalReceived = 0;
  int _carryoverCases = 0;
  int _totalWorkload = 0;
  int _activeOnTime = 0;
  int _activeOverdue = 0;
  int _completedOnTime = 0;
  int _completedLate = 0;
  int _pendingAtPeriodEnd = 0;

  final _months = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
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

  static const _categoryKeys = {
    'BASS Assistance': 'bass',
    'Barangay Documents': 'documents',
    'Community Services': 'community',
    'Beneficiary Registration': 'beneficiary',
    'VAW / BCPC Report': 'vaw',
    'Education Incentive': 'education',
    'Ad Hoc / Special Program': 'adhoc',
  };

  @override
  void initState() {
    super.initState();
    // Keep one stable stream. Reporting-period and category filters are
    // applied locally so switching filters cannot replace the stream with an
    // intermediate or index-failing Firestore query.
    _casesStream = FirebaseFirestore.instance.collection('cases').snapshots();
    _slaConfigStream = FirebaseFirestore.instance
        .collection('slaConfig')
        .snapshots();
  }

  DateTimeRange _getMonthRange(String month, int year) {
    final monthIndex = _months.indexOf(month);
    return DateTimeRange(
      start: DateTime(year, monthIndex + 1, 1),
      end: DateTime(year, monthIndex + 2, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMonth = _months[DateTime.now().month - 1];
    final month = _selectedMonth ?? currentMonth;
    final year = _selectedYear ?? DateTime.now().year;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Compliance Report',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Citizens' Charter compliance summary and breakdown.",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Filters
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 760
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 24) / 3,
                  child: DropdownButtonFormField<int>(
                    initialValue: year,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items:
                        List.generate(6, (index) => DateTime.now().year - index)
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value'),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => setState(() => _selectedYear = value),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth < 760
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 24) / 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: month,
                    decoration: const InputDecoration(
                      labelText: 'Reporting Month',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _months
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedMonth = v),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth < 760
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 24) / 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategory ?? 'All Categories',
                    decoration: const InputDecoration(
                      labelText: 'Service Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCategory = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Monthly workload includes cases received during the month and '
              'unfinished cases carried over from earlier months. Past months '
              'are evaluated as of the final day of that month; the current '
              'month is evaluated as of today.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),

          // Summary KPIs (from SLA data)
          StreamBuilder<QuerySnapshot>(
            stream: _slaConfigStream,
            builder: (context, configSnapshot) {
              final slaConfig = sla.buildSlaConfig(
                (configSnapshot.data?.docs ?? []).map(
                  (doc) => doc.data() as Map<String, dynamic>,
                ),
              );
              return StreamBuilder<QuerySnapshot>(
                stream: _casesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        'Could not load compliance data: ${snapshot.error}',
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  _totalReceived = 0;
                  _carryoverCases = 0;
                  _totalWorkload = 0;
                  _activeOnTime = 0;
                  _activeOverdue = 0;
                  _completedOnTime = 0;
                  _completedLate = 0;
                  _pendingAtPeriodEnd = 0;
                  var completedCases = 0;
                  var totalProcessingMilliseconds = 0;

                  final categoryBreakdown = <String, Map<String, int>>{};
                  final range = _getMonthRange(month, year);
                  final now = DateTime.now();
                  final periodIsCurrent =
                      year == now.year &&
                      _months.indexOf(month) + 1 == now.month;
                  final periodIsFuture = range.start.isAfter(now);
                  final asOf = periodIsCurrent
                      ? now
                      : range.end.subtract(const Duration(microseconds: 1));
                  final selectedCategoryKey =
                      _categoryKeys[_selectedCategory ?? 'All Categories'];

                  for (final doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final cat = data['serviceCategory'] ?? 'unknown';
                    final submittedAt = data['submissionTimestamp'] is Timestamp
                        ? (data['submissionTimestamp'] as Timestamp).toDate()
                        : null;

                    if (selectedCategoryKey != null &&
                        cat != selectedCategoryKey) {
                      continue;
                    }

                    if (submittedAt == null ||
                        periodIsFuture ||
                        !submittedAt.isBefore(range.end)) {
                      continue;
                    }

                    final status =
                        data['status'] as String? ?? 'pending_review';
                    final isCompleted =
                        status == 'released' || status == 'rejected';
                    final completedAt = isCompleted
                        ? _timestampDate(
                            data['statusUpdatedAt'] ?? data['lastUpdated'],
                          )
                        : null;
                    final wasCompletedBeforePeriod =
                        completedAt != null &&
                        completedAt.isBefore(range.start);
                    if (wasCompletedBeforePeriod) continue;

                    final receivedDuringPeriod = !submittedAt.isBefore(
                      range.start,
                    );
                    final carryover = submittedAt.isBefore(range.start);
                    final completedDuringPeriod =
                        completedAt != null &&
                        !completedAt.isBefore(range.start) &&
                        completedAt.isBefore(range.end);
                    final activeAtCutoff =
                        !submittedAt.isAfter(asOf) &&
                        (completedAt == null || completedAt.isAfter(asOf));
                    final deadline = sla.computeDeadline(
                      submittedAt,
                      cat,
                      data['serviceSubType'] ?? '',
                      config: slaConfig,
                    );
                    final completedOnTime =
                        completedDuringPeriod && !completedAt.isAfter(deadline);
                    final completedLate =
                        completedDuringPeriod && completedAt.isAfter(deadline);
                    final activeIsOverdue =
                        activeAtCutoff && asOf.isAfter(deadline);
                    final activeIsOnTime = activeAtCutoff && !activeIsOverdue;

                    _totalWorkload++;
                    if (receivedDuringPeriod) _totalReceived++;
                    if (carryover) _carryoverCases++;
                    if (activeIsOnTime) _activeOnTime++;
                    if (activeIsOverdue) _activeOverdue++;
                    if (completedOnTime) _completedOnTime++;
                    if (completedLate) _completedLate++;
                    if (activeAtCutoff) _pendingAtPeriodEnd++;
                    if (completedDuringPeriod &&
                        !completedAt.isBefore(submittedAt)) {
                      completedCases++;
                      totalProcessingMilliseconds += completedAt
                          .difference(submittedAt)
                          .inMilliseconds;
                    }

                    categoryBreakdown.putIfAbsent(
                      cat,
                      () => {
                        'workload': 0,
                        'received': 0,
                        'carryover': 0,
                        'completedOnTime': 0,
                        'completedLate': 0,
                        'pending': 0,
                      },
                    );
                    final breakdown = categoryBreakdown[cat]!;
                    breakdown['workload'] = breakdown['workload']! + 1;
                    if (receivedDuringPeriod) {
                      breakdown['received'] = breakdown['received']! + 1;
                    }
                    if (carryover) {
                      breakdown['carryover'] = breakdown['carryover']! + 1;
                    }
                    if (completedOnTime) {
                      breakdown['completedOnTime'] =
                          breakdown['completedOnTime']! + 1;
                    }
                    if (completedLate) {
                      breakdown['completedLate'] =
                          breakdown['completedLate']! + 1;
                    }
                    if (activeAtCutoff) {
                      breakdown['pending'] = breakdown['pending']! + 1;
                    }
                  }

                  // Store breakdown data for export
                  _breakdownData = categoryBreakdown.entries
                      .map((e) => {'category': e.key, ...e.value})
                      .toList();

                  final avgTime = completedCases == 0
                      ? 'N/A'
                      : _formatDuration(
                          Duration(
                            milliseconds:
                                totalProcessingMilliseconds ~/ completedCases,
                          ),
                        );
                  final completedInPeriod = _completedOnTime + _completedLate;
                  final complianceRate = completedInPeriod == 0
                      ? 'N/A'
                      : '${(_completedOnTime / completedInPeriod * 100).toStringAsFixed(1)}%';

                  return Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 1050
                              ? 4
                              : constraints.maxWidth >= 560
                              ? 2
                              : 1;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 12) /
                              columns;
                          final cards = [
                            KpiCard(
                              label: 'Received This Month',
                              value: '$_totalReceived',
                              icon: Icons.inbox,
                            ),
                            KpiCard(
                              label: 'Carryover Backlog',
                              value: '$_carryoverCases',
                              icon: Icons.history,
                            ),
                            KpiCard(
                              label: 'Total Workload',
                              value: '$_totalWorkload',
                              icon: Icons.work_outline,
                            ),
                            KpiCard(
                              label: 'Active On Time',
                              value: '$_activeOnTime',
                              accentColor: Colors.green,
                              icon: Icons.schedule,
                            ),
                            KpiCard(
                              label: 'Active Overdue',
                              value: '$_activeOverdue',
                              accentColor: Colors.red,
                              icon: Icons.error_outline,
                            ),
                            KpiCard(
                              label: 'Completed On Time',
                              value: '$_completedOnTime',
                              accentColor: Colors.green,
                              icon: Icons.check_circle,
                            ),
                            KpiCard(
                              label: 'Completed Late',
                              value: '$_completedLate',
                              accentColor: Colors.red,
                              icon: Icons.timer_off_outlined,
                            ),
                            KpiCard(
                              label: 'Pending at Period End',
                              value: '$_pendingAtPeriodEnd',
                              icon: Icons.pending_actions,
                            ),
                            KpiCard(
                              label: 'Avg Processing',
                              value: avgTime,
                              icon: Icons.timer,
                            ),
                            KpiCard(
                              label: 'Completion Compliance',
                              value: complianceRate,
                              accentColor: Colors.green,
                              icon: Icons.analytics_outlined,
                            ),
                          ];
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: cards
                                .map(
                                  (card) => SizedBox(width: width, child: card),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Breakdown table
                      const Text(
                        'Breakdown by Category',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kNavy,
                        ),
                      ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Category',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Workload',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Received',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Carryover',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Completed On Time',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Completed Late',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Pending',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (categoryBreakdown.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No data available for the selected period.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            else
                              ...categoryBreakdown.entries.map((entry) {
                                final cat = entry.key;
                                final d = entry.value;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          cat.toUpperCase(),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${d['workload']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${d['received']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${d['carryover']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${d['completedOnTime']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${d['completedLate']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${d['pending']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
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

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    }
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    return '${duration.inMinutes}m';
  }

  DateTime? _timestampDate(dynamic value) =>
      value is Timestamp ? value.toDate() : null;

  void _exportCsv() {
    if (_breakdownData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to export.')),
      );
      return;
    }
    ExportService.downloadCsv(
      headers: [
        'Category',
        'Total Workload',
        'Received',
        'Carryover',
        'Completed On Time',
        'Completed Late',
        'Pending at Period End',
        'Completion Compliance Rate',
      ],
      rows: _breakdownData.map<List<String>>((d) {
        final onTime = d['completedOnTime'] as int;
        final late = d['completedLate'] as int;
        final completed = onTime + late;
        final rate = completed > 0
            ? (onTime / completed * 100).toStringAsFixed(1)
            : '0.0';
        return <String>[
          (d['category'] as String).toUpperCase(),
          '${d['workload']}',
          '${d['received']}',
          '${d['carryover']}',
          '${d['completedOnTime']}',
          '${d['completedLate']}',
          '${d['pending']}',
          '$rate%',
        ];
      }).toList(),
      filename:
          'compliance_report_${DateTime.now().millisecondsSinceEpoch}.csv',
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
      month:
          '${_selectedMonth ?? _months[DateTime.now().month - 1]} '
          '${_selectedYear ?? DateTime.now().year}',
      breakdown: _breakdownData,
      totalReceived: _totalReceived,
      carryoverCases: _carryoverCases,
      totalWorkload: _totalWorkload,
      activeOnTime: _activeOnTime,
      activeOverdue: _activeOverdue,
      completedOnTime: _completedOnTime,
      completedLate: _completedLate,
      pendingAtPeriodEnd: _pendingAtPeriodEnd,
    );
  }
}
