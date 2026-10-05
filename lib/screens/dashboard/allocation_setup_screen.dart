import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../utils/budget_period.dart';

class AllocationSetupScreen extends StatefulWidget {
  const AllocationSetupScreen({super.key});

  @override
  State<AllocationSetupScreen> createState() => _AllocationSetupScreenState();
}

class _AllocationSetupScreenState extends State<AllocationSetupScreen> {
  final Map<String, TextEditingController> _amountControllers = {};
  bool _loading = false;
  late int _selectedFiscalYear;
  String? _selectedPeriod;
  List<String> _savedPeriods = [];

  final _defaultPrograms = const [
    'BASS – Medical Assistance',
    'BASS – Burial Assistance',
    'BASS – Drug Rehabilitation',
    'BASS – Fire Relief',
    'Senior Citizen Birthday',
    'PWD Birthday',
    'Education Incentive',
  ];

  @override
  void initState() {
    super.initState();
    _selectedFiscalYear = DateTime.now().year;
    _selectedPeriod =
        'FY $_selectedFiscalYear Q${((DateTime.now().month - 1) ~/ 3) + 1}';
    for (final p in _defaultPrograms) {
      _amountControllers[p] = TextEditingController(text: '0');
    }
    _loadSavedPeriods();
    _loadAllocationForPeriod(_selectedPeriod!);
  }

  Future<void> _loadSavedPeriods() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('budgetPrograms')
          .get();
      final periods = <String>{};
      for (final doc in snap.docs) {
        final period = (doc.data()['fiscalPeriod'] ?? '').toString().trim();
        if (period.isNotEmpty) periods.add(period);
      }
      if (mounted) {
        setState(() => _savedPeriods = periods.toList()..sort());
      }
    } catch (_) {}
  }

  List<int> get _fiscalYearOptions {
    final currentYear = DateTime.now().year;
    final years = <int>{
      currentYear - 1,
      currentYear,
      currentYear + 1,
      _selectedFiscalYear,
      ..._savedPeriods
          .map((period) => BudgetPeriod.parse(period).fiscalYear)
          .whereType<int>(),
    }.toList()..sort();
    return years;
  }

  List<String> get _periodOptions {
    final year = _selectedFiscalYear;
    return List.generate(4, (index) => 'FY $year Q${index + 1}');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Allocation Setup',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Set budget allocations per program per fiscal period.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mid-period adjustments require authorization and are logged in the audit trail.',
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
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
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  items: _fiscalYearOptions
                      .map(
                        (year) => DropdownMenuItem(
                          value: year,
                          child: Text('FY $year'),
                        ),
                      )
                      .toList(),
                  onChanged: (year) {
                    if (year == null) return;
                    const firstQuarter = 1;
                    final quarterPeriod = 'FY $year Q$firstQuarter';
                    setState(() {
                      _selectedFiscalYear = year;
                      _selectedPeriod = quarterPeriod;
                    });
                    _loadAllocationForPeriod(quarterPeriod);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${_selectedFiscalYear}_${_selectedPeriod ?? ''}',
                  ),
                  initialValue: _selectedPeriod,
                  decoration: const InputDecoration(
                    labelText: 'Period within Fiscal Year',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.date_range),
                  ),
                  items: _periodOptions
                      .map(
                        (period) => DropdownMenuItem(
                          value: period,
                          child: Text(BudgetPeriod.parse(period).scopeLabel),
                        ),
                      )
                      .toList(),
                  onChanged: (period) {
                    if (period == null) return;
                    setState(() => _selectedPeriod = period);
                    _loadAllocationForPeriod(period);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${BudgetPeriod.parse(_selectedPeriod ?? '').scopeLabel} allocation for FY $_selectedFiscalYear.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 20),

          const Text(
            'Program Allocations',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 12),

          ..._defaultPrograms.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _amountControllers[p],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: p,
                  prefixText: '₱ ',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Allocated:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '₱${_computeTotal().toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: kNavy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _saveAllocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save allocation changes',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAllocationForPeriod(String period) async {
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final selectedPeriod = BudgetPeriod.parse(period);
      final snap = await db.collection('budgetPrograms').get();

      // Ignore a slower request if the user selected another period while it
      // was loading.
      if (!mounted || _selectedPeriod != period) return;

      for (final p in _defaultPrograms) {
        _amountControllers[p]?.text = '0';
      }

      final latestByProgram = <String, QueryDocumentSnapshot>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final docPeriod = BudgetPeriod.fromData(data);
        if (docPeriod.fiscalYear != selectedPeriod.fiscalYear ||
            docPeriod.type != 'quarterly' ||
            docPeriod.quarter != selectedPeriod.quarter) {
          continue;
        }
        final name = data['name'] as String?;
        if (name == null || !_amountControllers.containsKey(name)) continue;
        final existing = latestByProgram[name];
        if (existing == null ||
            _lastUpdated(doc) > _lastUpdated(existing) ||
            (_lastUpdated(doc) == _lastUpdated(existing) &&
                doc.id.compareTo(existing.id) > 0)) {
          latestByProgram[name] = doc;
        }
      }

      for (final entry in latestByProgram.entries) {
        final data = entry.value.data() as Map<String, dynamic>;
        final allocated = (data['allocated'] as num?)?.toDouble() ?? 0;
        _amountControllers[entry.key]!.text = allocated.toStringAsFixed(0);
      }
    } catch (e) {
      debugPrint('Load allocation failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _computeTotal() {
    double total = 0;
    for (final c in _amountControllers.values) {
      total += double.tryParse(c.text) ?? 0;
    }
    return total;
  }

  Future<void> _saveAllocation() async {
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final period = _selectedPeriod!;
      final periodInfo = BudgetPeriod.parse(period);
      final batch = db.batch();

      for (final entry in _amountControllers.entries) {
        final amount = double.tryParse(entry.value.text) ?? 0;
        final snap = await db
            .collection('budgetPrograms')
            .where('name', isEqualTo: entry.key)
            .get();

        QueryDocumentSnapshot? existing;
        for (final document in snap.docs) {
          final documentData = document.data();
          final documentPeriod = BudgetPeriod.fromData(documentData);
          if (documentPeriod.fiscalYear != periodInfo.fiscalYear ||
              documentPeriod.type != 'quarterly' ||
              documentPeriod.quarter != periodInfo.quarter) {
            continue;
          }
          if (existing == null ||
              _lastUpdated(document) > _lastUpdated(existing) ||
              (_lastUpdated(document) == _lastUpdated(existing) &&
                  document.id.compareTo(existing.id) > 0)) {
            existing = document;
          }
        }

        // Update the newest existing record in place so program IDs referenced
        // by cases and transactions remain valid. Older duplicates are left
        // untouched and are ignored by overview/report screens.
        final existingData = existing?.data() as Map<String, dynamic>?;
        final utilized = (existingData?['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (existingData?['reserved'] as num?)?.toDouble() ?? 0;
        final thresholdPercent =
            (existingData?['thresholdPercent'] as num?)?.toDouble() ?? 10;
        final remaining = amount - utilized - reserved;
        final thresholdAmount = amount * thresholdPercent / 100;
        final status = remaining <= amount * 0.10
            ? budgetCritical
            : remaining <= thresholdAmount
            ? budgetLow
            : budgetHealthy;
        final ref =
            existing?.reference ?? db.collection('budgetPrograms').doc();
        batch.set(ref, {
          'name': entry.key,
          'fiscalPeriod': period,
          ...periodInfo.firestoreFields,
          'allocated': amount,
          'utilized': utilized,
          'reserved': reserved,
          'remaining': remaining,
          'thresholdPercent': thresholdPercent,
          'thresholdAmount': thresholdAmount,
          'status': status,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
      await _loadSavedPeriods();
      await _loadAllocationForPeriod(period);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Allocation saved.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _lastUpdated(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return (data['lastUpdated'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
  }

  @override
  void dispose() {
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
