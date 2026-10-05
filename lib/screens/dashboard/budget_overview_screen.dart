import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/budget_program_card.dart';
import '../../utils/budget_health.dart';
import '../../utils/budget_period.dart';

class BudgetOverviewScreen extends StatefulWidget {
  const BudgetOverviewScreen({super.key});

  @override
  State<BudgetOverviewScreen> createState() => _BudgetOverviewScreenState();
}

class _BudgetOverviewScreenState extends State<BudgetOverviewScreen> {
  static const _defaultPrograms = [
    'BASS – Medical Assistance',
    'BASS – Burial Assistance',
    'BASS – Drug Rehabilitation',
    'BASS – Fire Relief',
    'Senior Citizen Birthday',
    'PWD Birthday',
    'Education Incentive',
  ];

  int? _selectedFiscalYear;
  String? _selectedPeriod;

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
              'Could not load budget programs: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final allDocs = snapshot.data?.docs ?? [];
        final storedPeriods = <BudgetPeriod>[];
        for (final doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final parsed = BudgetPeriod.fromData(data);
          final label = parsed.label.isEmpty ? 'Unspecified' : parsed.label;
          storedPeriods.add(
            BudgetPeriod(
              label: label,
              fiscalYear: parsed.fiscalYear,
              type: parsed.type,
              quarter: parsed.quarter,
            ),
          );
        }
        final currentYear = DateTime.now().year;
        final fiscalYears = <int>{
          currentYear - 1,
          currentYear,
          currentYear + 1,
          ...storedPeriods.map((value) => value.fiscalYear).whereType<int>(),
        }.toList()..sort();
        final fiscalYear = _effectiveFiscalYear(fiscalYears);

        final periods = <BudgetPeriod>[];
        if (fiscalYear != null) {
          periods.add(BudgetPeriod.parse('FY $fiscalYear'));
          for (var quarter = 1; quarter <= 4; quarter++) {
            periods.add(BudgetPeriod.parse('FY $fiscalYear Q$quarter'));
          }
        }
        final period = _effectivePeriod(periods);
        final isAnnual = period?.isAnnual ?? false;
        final latestByProgramAndQuarter = <String, QueryDocumentSnapshot>{};

        for (final doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final docPeriod = BudgetPeriod.fromData(data);
          if (docPeriod.fiscalYear != fiscalYear ||
              docPeriod.type != 'quarterly' ||
              (!isAnnual && docPeriod.quarter != period?.quarter)) {
            continue;
          }

          final name = (data['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final key = '${name.toLowerCase()}|q${docPeriod.quarter}';
          final existing = latestByProgramAndQuarter[key];

          if (existing == null ||
              _lastUpdated(doc) > _lastUpdated(existing) ||
              (_lastUpdated(doc) == _lastUpdated(existing) &&
                  doc.id.compareTo(existing.id) > 0)) {
            latestByProgramAndQuarter[key] = doc;
          }
        }

        final programsByName = <String, _BudgetProgramView>{};
        for (final doc in latestByProgramAndQuarter.values) {
          final data = doc.data() as Map<String, dynamic>;
          final docPeriod = BudgetPeriod.fromData(data);
          final name = (data['name'] ?? '').toString().trim();
          final key = name.toLowerCase();
          final allocated = (data['allocated'] as num?)?.toDouble() ?? 0;
          final utilized = (data['utilized'] as num?)?.toDouble() ?? 0;
          final reserved = (data['reserved'] as num?)?.toDouble() ?? 0;
          final existing = programsByName[key];
          programsByName[key] = _BudgetProgramView(
            name: name,
            allocated: (existing?.allocated ?? 0) + allocated,
            utilized: (existing?.utilized ?? 0) + utilized,
            reserved: (existing?.reserved ?? 0) + reserved,
            documentId: isAnnual ? null : doc.id,
            quarterlyBudgets: [
              ...?existing?.quarterlyBudgets,
              _QuarterBudget(
                fiscalYear: docPeriod.fiscalYear!,
                quarter: docPeriod.quarter!,
                allocated: allocated,
                utilized: utilized,
                reserved: reserved,
              ),
            ],
          );
        }
        for (final name in _defaultPrograms) {
          programsByName.putIfAbsent(
            name.toLowerCase(),
            () => _BudgetProgramView(
              name: name,
              allocated: 0,
              utilized: 0,
              reserved: 0,
              documentId: null,
              quarterlyBudgets: const [],
            ),
          );
        }
        final programs = programsByName.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        double totalAllocated = 0;
        double totalUtilized = 0;
        double totalReserved = 0;
        int flagged = 0;
        for (final program in programs) {
          totalAllocated += program.allocated;
          totalUtilized += program.utilized;
          totalReserved += program.reserved;
          if (program.status == budgetLow || program.status == budgetCritical) {
            flagged++;
          }
        }
        final totalRemaining = totalAllocated - totalUtilized - totalReserved;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Budget Overview',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Social services budget allocation and utilization.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (fiscalYears.isNotEmpty && periods.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(fiscalYear),
                        initialValue: fiscalYear,
                        decoration: const InputDecoration(
                          labelText: 'Fiscal Year',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        items: fiscalYears
                            .map(
                              (year) => DropdownMenuItem(
                                value: year,
                                child: Text('FY $year'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedFiscalYear = value;
                              _selectedPeriod = null;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('${fiscalYear}_${period?.label}'),
                        initialValue: period?.label,
                        decoration: const InputDecoration(
                          labelText: 'Period within Fiscal Year',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.date_range),
                        ),
                        items: periods
                            .map(
                              (value) => DropdownMenuItem(
                                value: value.label,
                                child: Text(value.scopeLabel),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedPeriod = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  period?.isAnnual == true
                      ? 'Annual totals are calculated from Q1 + Q2 + Q3 + Q4 and cannot be edited directly.'
                      : '${period?.scopeLabel ?? ''} allocation for FY $fiscalYear.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 20),
              ],
              Row(
                children: [
                  Expanded(
                    child: KpiCard(
                      label: 'Total Allocated',
                      value: '₱${totalAllocated.toStringAsFixed(0)}',
                      icon: Icons.account_balance,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KpiCard(
                      label: 'Utilized',
                      value: '₱${totalUtilized.toStringAsFixed(0)}',
                      accentColor: Colors.orange,
                      icon: Icons.payments,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KpiCard(
                      label: 'Reserved for Release',
                      value: '₱${totalReserved.toStringAsFixed(0)}',
                      accentColor: Colors.blue,
                      icon: Icons.lock_clock,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KpiCard(
                      label: 'Available',
                      value: '₱${totalRemaining.toStringAsFixed(0)}',
                      accentColor: Colors.green,
                      icon: Icons.savings,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KpiCard(
                      label: 'Flagged',
                      value: '$flagged',
                      accentColor: flagged > 0 ? Colors.red : Colors.green,
                      icon: Icons.flag,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (flagged > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.pink.shade200),
                  ),
                  child: Text(
                    '$flagged program(s) are below the expected remaining '
                    'budget for the current checkpoint.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              const Text(
                'Budget per program',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
              const SizedBox(height: 12),
              if (programs.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No budget programs configured for this fiscal period.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ...programs.map((program) {
                  final destination = Uri(
                    path: '/dashboard/budget-details',
                    queryParameters: {
                      'program': program.name,
                      if (fiscalYear != null) 'year': '$fiscalYear',
                      if (!isAnnual && period?.quarter != null)
                        'quarter': '${period!.quarter}',
                    },
                  ).toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => context.go(destination),
                      child: BudgetProgramCard(
                        programName: program.name,
                        status: program.status,
                        allocated: program.allocated,
                        utilized: program.utilized,
                        reserved: program.reserved,
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  int? _effectiveFiscalYear(List<int> fiscalYears) {
    if (fiscalYears.isEmpty) return null;
    if (_selectedFiscalYear != null &&
        fiscalYears.contains(_selectedFiscalYear)) {
      return _selectedFiscalYear;
    }
    final currentYear = DateTime.now().year;
    return fiscalYears.contains(currentYear) ? currentYear : fiscalYears.last;
  }

  BudgetPeriod? _effectivePeriod(List<BudgetPeriod> periods) {
    if (periods.isEmpty) return null;
    if (_selectedPeriod != null) {
      for (final period in periods) {
        if (period.label == _selectedPeriod) return period;
      }
    }
    return periods.first;
  }

  int _lastUpdated(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return (data['lastUpdated'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
  }
}

extension on BudgetPeriod {
  bool get isAnnual => type == 'annual';
}

class _BudgetProgramView {
  final String name;
  final double allocated;
  final double utilized;
  final double reserved;
  final String? documentId;
  final List<_QuarterBudget> quarterlyBudgets;

  const _BudgetProgramView({
    required this.name,
    required this.allocated,
    required this.utilized,
    required this.reserved,
    required this.documentId,
    required this.quarterlyBudgets,
  });

  String get status {
    final now = DateTime.now();
    return worstBudgetHealth(
      quarterlyBudgets.map(
        (budget) => calculateBudgetHealth(
          allocated: budget.allocated,
          utilized: budget.utilized + budget.reserved,
          fiscalYear: budget.fiscalYear,
          quarter: budget.quarter,
          asOf: now,
        ),
      ),
    );
  }
}

class _QuarterBudget {
  final int fiscalYear;
  final int quarter;
  final double allocated;
  final double utilized;
  final double reserved;

  const _QuarterBudget({
    required this.fiscalYear,
    required this.quarter,
    required this.allocated,
    required this.utilized,
    required this.reserved,
  });
}
