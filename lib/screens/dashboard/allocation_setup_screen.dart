import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../utils/budget_period.dart';
import '../../utils/budget_health.dart';

class AllocationSetupScreen extends StatefulWidget {
  const AllocationSetupScreen({super.key});

  @override
  State<AllocationSetupScreen> createState() => _AllocationSetupScreenState();
}

class _AllocationSetupScreenState extends State<AllocationSetupScreen> {
  final Map<String, TextEditingController> _amountControllers = {};
  final TextEditingController _periodBudgetController = TextEditingController(
    text: '0',
  );
  final TextEditingController _transferAmountController =
      TextEditingController();
  final Map<String, double> _utilizedByProgram = {};
  final Map<String, double> _reservedByProgram = {};
  bool _loading = false;
  late int _selectedFiscalYear;
  String? _selectedPeriod;
  List<String> _savedPeriods = [];
  String? _transferFrom;
  String? _transferTo;

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
      _utilizedByProgram[p] = 0;
      _reservedByProgram[p] = 0;
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

  bool get _selectedPeriodIsLocked => isPastBudgetQuarter(
    BudgetPeriod.parse(_selectedPeriod ?? ''),
    DateTime.now(),
  );

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
          if (_selectedPeriodIsLocked) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This fiscal quarter has already ended. Its allocations '
                      'are read-only to preserve historical budget records.',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

          Builder(
            builder: (context) {
              final periodBudget =
                  double.tryParse(_periodBudgetController.text) ?? 0;
              final totalAllocated = _computeTotal();
              final exceedsBudget = totalAllocated > periodBudget;
              final hasUnallocated = totalAllocated < periodBudget;
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: TextField(
                  controller: _periodBudgetController,
                  enabled: !_selectedPeriodIsLocked && !_loading,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Total budget for this fiscal period',
                    prefixText: '₱ ',
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                    suffixIcon: _selectedPeriodIsLocked
                        ? const Icon(Icons.lock_outline, size: 18)
                        : exceedsBudget
                        ? const Icon(Icons.error_outline, color: Colors.red)
                        : null,
                    errorText: exceedsBudget
                        ? 'Program allocations exceed this period budget by '
                              '₱${(totalAllocated - periodBudget).toStringAsFixed(2)}.'
                        : hasUnallocated
                        ? 'Distribute the remaining '
                              '₱${(periodBudget - totalAllocated).toStringAsFixed(2)} among the program funds.'
                        : null,
                    helperText:
                        'Set the complete budget ceiling for ${BudgetPeriod.parse(_selectedPeriod ?? '').scopeLabel}, FY $_selectedFiscalYear.',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              );
            },
          ),

          ..._defaultPrograms.map(_buildAllocationField),

          const SizedBox(height: 8),
          _buildTransferPanel(),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _summaryRow('Period Budget:', _periodBudget),
                const SizedBox(height: 8),
                _summaryRow('Total Allocated:', _computeTotal()),
                const Divider(height: 20),
                _summaryRow(
                  'Unallocated Balance:',
                  _periodBudget - _computeTotal(),
                  valueColor: _periodBudget - _computeTotal() < 0
                      ? Colors.red
                      : Colors.green.shade700,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading || _selectedPeriodIsLocked
                  ? null
                  : _saveAllocation,
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
      final results = await Future.wait([
        db.collection('budgetPrograms').get(),
        db.collection('budgetPeriods').doc(_periodDocumentId(period)).get(),
      ]);
      final snap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final periodDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;

      // Ignore a slower request if the user selected another period while it
      // was loading.
      if (!mounted || _selectedPeriod != period) return;

      for (final p in _defaultPrograms) {
        _amountControllers[p]?.text = '0';
        _utilizedByProgram[p] = 0;
        _reservedByProgram[p] = 0;
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
        final utilized = (data['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (data['reserved'] as num?)?.toDouble() ?? 0;
        _amountControllers[entry.key]!.text = allocated.toStringAsFixed(0);
        _utilizedByProgram[entry.key] = utilized;
        _reservedByProgram[entry.key] = reserved;
      }
      final savedPeriodBudget = (periodDoc.data()?['totalBudget'] as num?)
          ?.toDouble();
      // Existing installations have no budgetPeriods record. Starting with
      // the currently allocated total preserves those allocations until the
      // captain explicitly changes the new period ceiling.
      _periodBudgetController.text = (savedPeriodBudget ?? _computeTotal())
          .toStringAsFixed(0);
      if (mounted) setState(() {});
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

  double get _periodBudget =>
      double.tryParse(_periodBudgetController.text) ?? 0;

  String _periodDocumentId(String period) =>
      period.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  Widget _summaryRow(String label, double amount, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        Text(
          '₱${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: valueColor ?? kNavy,
          ),
        ),
      ],
    );
  }

  Widget _buildAllocationField(String program) {
    final proposed = double.tryParse(_amountControllers[program]!.text) ?? 0;
    final utilized = _utilizedByProgram[program] ?? 0;
    final reserved = _reservedByProgram[program] ?? 0;
    final committed = utilized + reserved;
    final belowCommitted = proposed < committed;
    final period = BudgetPeriod.parse(_selectedPeriod ?? '');
    final health = calculateBudgetHealth(
      allocated: proposed,
      utilized: committed,
      fiscalYear: period.fiscalYear ?? _selectedFiscalYear,
      quarter: period.quarter ?? 1,
      asOf: DateTime.now(),
    );
    final isCritical =
        !belowCommitted && proposed > 0 && health == budgetCritical;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _amountControllers[program],
        enabled: !_selectedPeriodIsLocked && !_loading,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: program,
          prefixText: '₱ ',
          suffixIcon: _selectedPeriodIsLocked
              ? const Icon(Icons.lock_outline, size: 18)
              : belowCommitted || isCritical
              ? Icon(
                  belowCommitted ? Icons.error_outline : Icons.warning_amber,
                  color: belowCommitted ? Colors.red : Colors.orange,
                )
              : null,
          errorText: belowCommitted
              ? 'Must be at least ₱${committed.toStringAsFixed(2)} '
                    '(₱${utilized.toStringAsFixed(2)} used + '
                    '₱${reserved.toStringAsFixed(2)} on hold).'
              : null,
          helperText: isCritical
              ? 'Warning: this allocation would be Critical after used and on-hold amounts.'
              : 'Used: ₱${utilized.toStringAsFixed(2)}  •  On hold: ₱${reserved.toStringAsFixed(2)}',
          helperStyle: isCritical
              ? TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                )
              : null,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTransferPanel() {
    final fromAllocation = _transferFrom == null
        ? 0.0
        : double.tryParse(_amountControllers[_transferFrom]!.text) ?? 0;
    final fromCommitted = _transferFrom == null
        ? 0.0
        : (_utilizedByProgram[_transferFrom] ?? 0) +
              (_reservedByProgram[_transferFrom] ?? 0);
    final transferable = (fromAllocation - fromCommitted)
        .clamp(0, double.infinity)
        .toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        border: Border.all(color: Colors.blueGrey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.swap_horiz, color: kNavy),
              SizedBox(width: 8),
              Text(
                'Transfer Between Program Funds',
                style: TextStyle(
                  color: kNavy,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Move available allocation without changing the total period budget. Used and on-hold funds cannot be transferred.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _transferFrom,
                  decoration: const InputDecoration(
                    labelText: 'From fund',
                    border: OutlineInputBorder(),
                  ),
                  items: _defaultPrograms
                      .map(
                        (program) => DropdownMenuItem(
                          value: program,
                          child: Text(program, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _selectedPeriodIsLocked || _loading
                      ? null
                      : (value) => setState(() {
                          _transferFrom = value;
                          if (_transferTo == value) _transferTo = null;
                        }),
                ),
              ),
              const Icon(Icons.arrow_forward, color: kNavy),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('transfer_to_${_transferFrom ?? ''}'),
                  initialValue: _transferTo,
                  decoration: const InputDecoration(
                    labelText: 'To fund',
                    border: OutlineInputBorder(),
                  ),
                  items: _defaultPrograms
                      .where((program) => program != _transferFrom)
                      .map(
                        (program) => DropdownMenuItem(
                          value: program,
                          child: Text(program, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _selectedPeriodIsLocked || _loading
                      ? null
                      : (value) => setState(() => _transferTo = value),
                ),
              ),
              SizedBox(
                width: 190,
                child: TextField(
                  controller: _transferAmountController,
                  enabled: !_selectedPeriodIsLocked && !_loading,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Transfer amount',
                    prefixText: '₱ ',
                    helperText: _transferFrom == null
                        ? 'Select a source fund'
                        : 'Available: ₱${transferable.toStringAsFixed(2)}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _selectedPeriodIsLocked || _loading
                    ? null
                    : _applyTransfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Apply transfer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _applyTransfer() {
    final from = _transferFrom;
    final to = _transferTo;
    final amount = double.tryParse(_transferAmountController.text);
    if (from == null || to == null || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select both funds and enter a valid transfer amount.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final sourceAllocation =
        double.tryParse(_amountControllers[from]!.text) ?? 0;
    final destinationAllocation =
        double.tryParse(_amountControllers[to]!.text) ?? 0;
    final committed =
        (_utilizedByProgram[from] ?? 0) + (_reservedByProgram[from] ?? 0);
    final transferable = sourceAllocation - committed;
    if (amount > transferable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only ₱${transferable.clamp(0, double.infinity).toStringAsFixed(2)} '
            'is available to transfer from $from.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _amountControllers[from]!.text = (sourceAllocation - amount)
          .toStringAsFixed(2);
      _amountControllers[to]!.text = (destinationAllocation + amount)
          .toStringAsFixed(2);
      _transferAmountController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '₱${amount.toStringAsFixed(2)} moved from $from to $to. Save the allocation changes to confirm.',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _saveAllocation() async {
    if (_selectedPeriodIsLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Past fiscal quarters are locked and cannot be changed.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final period = _selectedPeriod!;
      final periodInfo = BudgetPeriod.parse(period);
      final periodBudget = _periodBudget;
      final totalAllocated = _computeTotal();
      if (periodBudget < 0) {
        throw StateError('The fiscal-period budget cannot be negative.');
      }
      if ((totalAllocated - periodBudget).abs() > 0.009) {
        throw StateError(
          'The entire fiscal-period budget must be distributed. Program '
          'allocations must equal the period budget.',
        );
      }
      final batch = db.batch();
      final criticalPrograms = <String>[];
      var totalUtilized = 0.0;
      var totalReserved = 0.0;

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
        final committed = utilized + reserved;
        totalUtilized += utilized;
        totalReserved += reserved;
        if (amount < committed) {
          throw StateError(
            '${entry.key} cannot be lower than '
            '₱${committed.toStringAsFixed(2)} '
            '(used + on hold).',
          );
        }
        final remaining = amount - utilized - reserved;
        final thresholdAmount = amount * thresholdPercent / 100;
        final health = calculateBudgetHealth(
          allocated: amount,
          utilized: committed,
          fiscalYear: periodInfo.fiscalYear ?? _selectedFiscalYear,
          quarter: periodInfo.quarter ?? 1,
          asOf: DateTime.now(),
        );
        if (amount > 0 && health == budgetCritical) {
          criticalPrograms.add(entry.key);
        }
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
          'status': health,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (periodBudget < totalUtilized + totalReserved) {
        throw StateError(
          'The fiscal-period budget cannot be lower than the total used and '
          'on-hold amount of '
          '₱${(totalUtilized + totalReserved).toStringAsFixed(2)}.',
        );
      }

      batch.set(
        db.collection('budgetPeriods').doc(_periodDocumentId(period)),
        {
          'fiscalPeriod': period,
          ...periodInfo.firestoreFields,
          'totalBudget': periodBudget,
          'totalAllocated': totalAllocated,
          'totalUtilized': totalUtilized,
          'totalReserved': totalReserved,
          'unallocatedBalance': periodBudget - totalAllocated,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (criticalPrograms.isNotEmpty && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Critical budget warning'),
            content: Text(
              'The proposed allocation will leave the following budget(s) '
              'in Critical condition after used and on-hold amounts:\n\n'
              '${criticalPrograms.map((name) => '• $name').join('\n')}\n\n'
              'Do you still want to save these allocations?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Review amounts'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
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
    _periodBudgetController.dispose();
    _transferAmountController.dispose();
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
