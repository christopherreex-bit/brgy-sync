import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/export_service.dart';
import '../../utils/budget_period.dart';
import '../../utils/constants.dart';

class ExpenditureSummaryScreen extends StatefulWidget {
  const ExpenditureSummaryScreen({super.key});

  @override
  State<ExpenditureSummaryScreen> createState() =>
      _ExpenditureSummaryScreenState();
}

class _ExpenditureSummaryScreenState extends State<ExpenditureSummaryScreen> {
  static const _defaultPrograms = [
    'BASS – Medical Assistance',
    'BASS – Burial Assistance',
    'BASS – Drug Rehabilitation',
    'BASS – Fire Relief',
    'Senior Citizen Birthday',
    'PWD Birthday',
    'Education Incentive',
  ];

  late int _selectedFiscalYear;
  String _selectedPeriod = 'annual';
  String _selectedCategory = 'All Categories';
  List<Map<String, dynamic>> _programData = [];
  double _totalAllocated = 0;
  double _totalUtilized = 0;
  double _totalReserved = 0;
  double _totalRemaining = 0;

  @override
  void initState() {
    super.initState();
    _selectedFiscalYear = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('budgetPrograms')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load expenditure data: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final currentYear = DateTime.now().year;
        final fiscalYears = <int>{
          currentYear - 1,
          currentYear,
          currentYear + 1,
          _selectedFiscalYear,
          ...docs
              .map(
                (doc) => BudgetPeriod.fromData(
                  doc.data() as Map<String, dynamic>,
                ).fiscalYear,
              )
              .whereType<int>(),
        }.toList()..sort();

        final selectedQuarter = _selectedPeriod == 'annual'
            ? null
            : int.parse(_selectedPeriod.substring(1));
        final latestByProgramAndQuarter = <String, QueryDocumentSnapshot>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final period = BudgetPeriod.fromData(data);
          if (period.fiscalYear != _selectedFiscalYear ||
              period.type != 'quarterly' ||
              (selectedQuarter != null && period.quarter != selectedQuarter)) {
            continue;
          }

          final canonicalName = _canonicalProgramName(
            (data['name'] ?? '').toString(),
          );
          if (canonicalName.isEmpty ||
              !_matchesCategory(canonicalName, _selectedCategory)) {
            continue;
          }

          final key = '${canonicalName.toLowerCase()}|q${period.quarter}';
          final existing = latestByProgramAndQuarter[key];
          if (existing == null ||
              _lastUpdated(doc) > _lastUpdated(existing) ||
              (_lastUpdated(doc) == _lastUpdated(existing) &&
                  doc.id.compareTo(existing.id) > 0)) {
            latestByProgramAndQuarter[key] = doc;
          }
        }

        final totalsByProgram = <String, Map<String, dynamic>>{};
        for (final doc in latestByProgramAndQuarter.values) {
          final data = doc.data() as Map<String, dynamic>;
          final name = _canonicalProgramName((data['name'] ?? '').toString());
          final key = name.toLowerCase();
          final allocated = (data['allocated'] as num?)?.toDouble() ?? 0;
          final utilized = (data['utilized'] as num?)?.toDouble() ?? 0;
          final reserved = (data['reserved'] as num?)?.toDouble() ?? 0;
          final existing = totalsByProgram[key];
          totalsByProgram[key] = {
            'name': name,
            'allocated': (existing?['allocated'] as double? ?? 0) + allocated,
            'utilized': (existing?['utilized'] as double? ?? 0) + utilized,
            'reserved': (existing?['reserved'] as double? ?? 0) + reserved,
          };
        }

        for (final name in _defaultPrograms.where(
          (name) => _matchesCategory(name, _selectedCategory),
        )) {
          totalsByProgram.putIfAbsent(
            name.toLowerCase(),
            () => {
              'name': name,
              'allocated': 0.0,
              'utilized': 0.0,
              'reserved': 0.0,
            },
          );
        }

        _programData =
            totalsByProgram.values.map((program) {
              final allocated = program['allocated'] as double;
              final utilized = program['utilized'] as double;
              final reserved = program['reserved'] as double;
              return {...program, 'remaining': allocated - utilized - reserved};
            }).toList()..sort(
              (a, b) => (a['name'] as String).compareTo(b['name'] as String),
            );

        _totalAllocated = _programData.fold(
          0,
          (total, item) => total + (item['allocated'] as double),
        );
        _totalUtilized = _programData.fold(
          0,
          (total, item) => total + (item['utilized'] as double),
        );
        _totalReserved = _programData.fold(
          0,
          (total, item) => total + (item['reserved'] as double),
        );
        _totalRemaining = _totalAllocated - _totalUtilized - _totalReserved;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Expenditure Summary',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Budget expenditure breakdown by program and period.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(_selectedFiscalYear),
                      initialValue: _selectedFiscalYear,
                      decoration: const InputDecoration(
                        labelText: 'Fiscal Year',
                        border: OutlineInputBorder(),
                      ),
                      items: fiscalYears
                          .map(
                            (year) => DropdownMenuItem(
                              value: year,
                              child: Text('FY $year'),
                            ),
                          )
                          .toList(),
                      onChanged: (year) {
                        if (year != null) {
                          setState(() => _selectedFiscalYear = year);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('${_selectedFiscalYear}_$_selectedPeriod'),
                      initialValue: _selectedPeriod,
                      decoration: const InputDecoration(
                        labelText: 'Period',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem<String>(
                          value: 'annual',
                          child: Text('Annual'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'q1',
                          child: Text('Q1'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'q2',
                          child: Text('Q2'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'q3',
                          child: Text('Q3'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'q4',
                          child: Text('Q4'),
                        ),
                      ],
                      onChanged: (period) {
                        if (period != null) {
                          setState(() => _selectedPeriod = period);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          const [
                                'All Categories',
                                'BASS',
                                'Senior Citizen',
                                'PWD',
                                'Education',
                              ]
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                      onChanged: (category) {
                        if (category != null) {
                          setState(() => _selectedCategory = category);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                selectedQuarter == null
                    ? 'Annual totals equal Q1 + Q2 + Q3 + Q4 for FY $_selectedFiscalYear.'
                    : 'Showing Q$selectedQuarter for FY $_selectedFiscalYear.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 20),
              _buildTable(),
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.download),
                    label: const Text('Export (.xlsx)'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _exportPdf,
                    icon: const Icon(Icons.download),
                    label: const Text('Download PDF'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    'Program',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Expanded(child: _TableHeading('Allocated')),
                Expanded(child: _TableHeading('Utilized')),
                Expanded(child: _TableHeading('Reserved')),
                Expanded(child: _TableHeading('Available')),
              ],
            ),
          ),
          ..._programData.map(
            (program) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      program['name'] as String,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(child: _moneyCell(program['allocated'] as double)),
                  Expanded(child: _moneyCell(program['utilized'] as double)),
                  Expanded(child: _moneyCell(program['reserved'] as double)),
                  Expanded(child: _moneyCell(program['remaining'] as double)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Expanded(flex: 3, child: _TableHeading('TOTAL')),
                Expanded(child: _moneyCell(_totalAllocated, bold: true)),
                Expanded(child: _moneyCell(_totalUtilized, bold: true)),
                Expanded(child: _moneyCell(_totalReserved, bold: true)),
                Expanded(child: _moneyCell(_totalRemaining, bold: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyCell(double value, {bool bold = false}) {
    return Text(
      '₱${value.toStringAsFixed(0)}',
      style: TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  String _canonicalProgramName(String rawName) {
    final normalized = rawName.trim().toLowerCase();
    if (normalized.contains('medical')) return _defaultPrograms[0];
    if (normalized.contains('burial')) return _defaultPrograms[1];
    if (normalized.contains('drug rehabilitation')) return _defaultPrograms[2];
    if (normalized.contains('fire relief')) return _defaultPrograms[3];
    if (normalized.contains('senior') && normalized.contains('birthday')) {
      return _defaultPrograms[4];
    }
    if (normalized.contains('pwd') && normalized.contains('birthday')) {
      return _defaultPrograms[5];
    }
    if (normalized.contains('education')) return _defaultPrograms[6];
    return rawName.trim();
  }

  bool _matchesCategory(String programName, String category) {
    if (category == 'All Categories') return true;
    final normalized = programName.toLowerCase();
    return switch (category) {
      'BASS' =>
        normalized.contains('bass') ||
            normalized.contains('medical') ||
            normalized.contains('burial') ||
            normalized.contains('drug rehabilitation') ||
            normalized.contains('fire relief'),
      'Senior Citizen' => normalized.contains('senior'),
      'PWD' => normalized.contains('pwd'),
      'Education' => normalized.contains('education'),
      _ => true,
    };
  }

  int _lastUpdated(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return (data['lastUpdated'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
  }

  void _exportCsv() {
    ExportService.downloadCsv(
      headers: [
        'Program',
        'Allocated',
        'Utilized',
        'Reserved for Release',
        'Available',
      ],
      rows: _programData
          .map<List<String>>(
            (program) => [
              program['name'] as String,
              '₱${(program['allocated'] as double).toStringAsFixed(0)}',
              '₱${(program['utilized'] as double).toStringAsFixed(0)}',
              '₱${(program['reserved'] as double).toStringAsFixed(0)}',
              '₱${(program['remaining'] as double).toStringAsFixed(0)}',
            ],
          )
          .toList(),
      filename:
          'expenditure_summary_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Expenditure summary exported as CSV.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _exportPdf() {
    ExportService.generateExpenditurePdf(
      programData: _programData,
      totalAllocated: _totalAllocated,
      totalUtilized: _totalUtilized,
      totalReserved: _totalReserved,
      totalRemaining: _totalRemaining,
    );
  }
}

class _TableHeading extends StatelessWidget {
  final String text;

  const _TableHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
    );
  }
}
