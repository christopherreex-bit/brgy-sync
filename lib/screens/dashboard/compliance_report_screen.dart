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
          FilledButton.icon(
            onPressed: _exportReport,
            icon: const Icon(Icons.download),
            label: const Text('Export'),
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

  Future<void> _exportReport() async {
    final now = DateTime.now();
    var startYear = _selectedYear ?? now.year;
    var startMonth = _selectedMonth == null
        ? 1
        : _months.indexOf(_selectedMonth!) + 1;
    var endYear = _selectedYear ?? now.year;
    var endMonth = _selectedMonth == null ? now.month : startMonth;
    var format = 'excel';
    final years = List.generate(10, (index) => now.year - index);
    final selection =
        await showDialog<
          ({
            int startYear,
            int startMonth,
            int endYear,
            int endMonth,
            String format,
          })
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Export compliance report'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'From',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: startMonth,
                            decoration: const InputDecoration(
                              labelText: 'Month',
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(
                              12,
                              (index) => DropdownMenuItem(
                                value: index + 1,
                                child: Text(_months[index]),
                              ),
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() => startMonth = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: startYear,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                              border: OutlineInputBorder(),
                            ),
                            items: years
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => startYear = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'To',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: endMonth,
                            decoration: const InputDecoration(
                              labelText: 'Month',
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(
                              12,
                              (index) => DropdownMenuItem(
                                value: index + 1,
                                child: Text(_months[index]),
                              ),
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => endMonth = value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: endYear,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                              border: OutlineInputBorder(),
                            ),
                            items: years
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => endYear = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: format,
                      decoration: const InputDecoration(
                        labelText: 'File format',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'excel',
                          child: Text('Excel-compatible spreadsheet (.csv)'),
                        ),
                        DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => format = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final start = DateTime(startYear, startMonth);
                    final end = DateTime(endYear, endMonth);
                    if (end.isBefore(start)) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'The end month cannot be before the start month.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, (
                      startYear: startYear,
                      startMonth: startMonth,
                      endYear: endYear,
                      endMonth: endMonth,
                      format: format,
                    ));
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),
        );
    if (selection == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing compliance range report…')),
    );
    try {
      final caseSnapshot = await FirebaseFirestore.instance
          .collection('cases')
          .get();
      final configSnapshot = await FirebaseFirestore.instance
          .collection('slaConfig')
          .get();
      final config = sla.buildSlaConfig(
        configSnapshot.docs.map((document) => document.data()),
      );
      final start = DateTime(selection.startYear, selection.startMonth, 1);
      final end = DateTime(selection.endYear, selection.endMonth + 1, 1);
      final metrics = _calculateRangeMetrics(
        caseSnapshot.docs,
        DateTimeRange(start: start, end: end),
        config,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      if (metrics.breakdown.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data exists in that month range.')),
        );
        return;
      }
      final rangeLabel = selection.startYear == selection.endYear
          ? '${_months[selection.startMonth - 1]}–${_months[selection.endMonth - 1]} ${selection.startYear}'
          : '${_months[selection.startMonth - 1]} ${selection.startYear}–${_months[selection.endMonth - 1]} ${selection.endYear}';
      if (selection.format == 'pdf') {
        ExportService.generateCompliancePdf(
          month: rangeLabel,
          breakdown: metrics.breakdown,
          totalReceived: metrics.received,
          carryoverCases: metrics.carryover,
          totalWorkload: metrics.workload,
          activeOnTime: metrics.activeOnTime,
          activeOverdue: metrics.activeOverdue,
          completedOnTime: metrics.completedOnTime,
          completedLate: metrics.completedLate,
          pendingAtPeriodEnd: metrics.pending,
        );
      } else {
        _downloadRangeCsv(metrics, selection, rangeLabel);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export report: $error')),
      );
    }
  }

  _ComplianceRangeMetrics _calculateRangeMetrics(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    DateTimeRange range,
    sla.SlaConfigMap config,
  ) {
    final now = DateTime.now();
    if (range.start.isAfter(now)) return _ComplianceRangeMetrics();
    final endCutoff = range.end.isAfter(now)
        ? now
        : range.end.subtract(const Duration(microseconds: 1));
    final categoryKey = _categoryKeys[_selectedCategory ?? 'All Categories'];
    final metrics = _ComplianceRangeMetrics();
    for (final document in documents) {
      final data = document.data();
      final category = (data['serviceCategory'] ?? 'unknown').toString();
      if (categoryKey != null && category != categoryKey) continue;
      final submitted = _timestampDate(data['submissionTimestamp']);
      if (submitted == null ||
          submitted.isAfter(endCutoff) ||
          !submitted.isBefore(range.end)) {
        continue;
      }
      final status = (data['status'] ?? 'pending_review').toString();
      final terminal = status == 'released' || status == 'rejected';
      final completed = terminal
          ? _timestampDate(data['statusUpdatedAt'] ?? data['lastUpdated'])
          : null;
      if (completed != null && completed.isBefore(range.start)) continue;

      final received = !submitted.isBefore(range.start);
      final carryover = submitted.isBefore(range.start);
      final completedInRange =
          completed != null &&
          !completed.isBefore(range.start) &&
          completed.isBefore(range.end);
      final activeAtEnd = completed == null || completed.isAfter(endCutoff);
      final deadline = sla.computeDeadline(
        submitted,
        category,
        (data['serviceSubType'] ?? '').toString(),
        config: config,
      );
      final completedOnTime = completedInRange && !completed.isAfter(deadline);
      final completedLate = completedInRange && completed.isAfter(deadline);
      final activeOverdue = activeAtEnd && endCutoff.isAfter(deadline);

      metrics.workload++;
      if (received) metrics.received++;
      if (carryover) metrics.carryover++;
      if (activeAtEnd && !activeOverdue) metrics.activeOnTime++;
      if (activeOverdue) metrics.activeOverdue++;
      if (completedOnTime) metrics.completedOnTime++;
      if (completedLate) metrics.completedLate++;
      if (activeAtEnd) metrics.pending++;

      final breakdown = metrics.byCategory.putIfAbsent(
        category,
        () => {
          'workload': 0,
          'received': 0,
          'carryover': 0,
          'completedOnTime': 0,
          'completedLate': 0,
          'pending': 0,
        },
      );
      breakdown['workload'] = breakdown['workload']! + 1;
      if (received) breakdown['received'] = breakdown['received']! + 1;
      if (carryover) breakdown['carryover'] = breakdown['carryover']! + 1;
      if (completedOnTime) {
        breakdown['completedOnTime'] = breakdown['completedOnTime']! + 1;
      }
      if (completedLate) {
        breakdown['completedLate'] = breakdown['completedLate']! + 1;
      }
      if (activeAtEnd) breakdown['pending'] = breakdown['pending']! + 1;
    }
    return metrics;
  }

  void _downloadRangeCsv(
    _ComplianceRangeMetrics metrics,
    ({int startYear, int startMonth, int endYear, int endMonth, String format})
    selection,
    String rangeLabel,
  ) {
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
      rows: metrics.breakdown.map((data) {
        final onTime = data['completedOnTime'] as int;
        final late = data['completedLate'] as int;
        final completed = onTime + late;
        return <String>[
          (data['category'] as String).toUpperCase(),
          '${data['workload']}',
          '${data['received']}',
          '${data['carryover']}',
          '$onTime',
          '$late',
          '${data['pending']}',
          completed == 0
              ? 'N/A'
              : '${(onTime / completed * 100).toStringAsFixed(1)}%',
        ];
      }).toList(),
      filename:
          'compliance_${selection.startYear}-${selection.startMonth.toString().padLeft(2, '0')}_to_${selection.endYear}-${selection.endMonth.toString().padLeft(2, '0')}.csv',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$rangeLabel compliance report downloaded.'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _ComplianceRangeMetrics {
  int received = 0;
  int carryover = 0;
  int workload = 0;
  int activeOnTime = 0;
  int activeOverdue = 0;
  int completedOnTime = 0;
  int completedLate = 0;
  int pending = 0;
  final Map<String, Map<String, int>> byCategory = {};

  List<Map<String, dynamic>> get breakdown => byCategory.entries
      .map((entry) => <String, dynamic>{'category': entry.key, ...entry.value})
      .toList();
}
