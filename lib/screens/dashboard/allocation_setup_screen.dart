import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';

class AllocationSetupScreen extends StatefulWidget {
  const AllocationSetupScreen({super.key});

  @override
  State<AllocationSetupScreen> createState() => _AllocationSetupScreenState();
}

class _AllocationSetupScreenState extends State<AllocationSetupScreen> {
  final _periodCtrl = TextEditingController(text: 'FY ${DateTime.now().year}');
  final Map<String, TextEditingController> _amountControllers = {};
  bool _loading = false;

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
    for (final p in _defaultPrograms) {
      _amountControllers[p] = TextEditingController(text: '0');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Allocation Setup',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Set budget allocations per program per fiscal period.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
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

          TextField(
            controller: _periodCtrl,
            decoration: const InputDecoration(
              labelText: 'Fiscal Period',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.calendar_today),
            ),
          ),
          const SizedBox(height: 20),

          const Text('Program Allocations',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 12),

          ..._defaultPrograms.map((p) => Padding(
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
              )),

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
                const Text('Total Allocated:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  '₱${_computeTotal().toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kNavy),
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
              style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save allocation changes', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
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
      final period = _periodCtrl.text.trim();
      final batch = db.batch();

      for (final entry in _amountControllers.entries) {
        final amount = double.tryParse(entry.value.text) ?? 0;
        final snap = await db
            .collection('budgetPrograms')
            .where('name', isEqualTo: entry.key)
            .where('fiscalPeriod', isEqualTo: period)
            .get();

        if (snap.docs.isNotEmpty) {
          batch.update(snap.docs.first.reference, {
            'allocated': amount,
            'remaining': amount - (snap.docs.first.data()['utilized'] as num?)?.toDouble() ?? 0,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        } else {
          final ref = db.collection('budgetPrograms').doc();
          batch.set(ref, {
            'name': entry.key,
            'fiscalPeriod': period,
            'allocated': amount,
            'utilized': 0,
            'remaining': amount,
            'thresholdPercent': 10,
            'thresholdAmount': amount * 0.1,
            'status': 'healthy',
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allocation saved.'), backgroundColor: Colors.green),
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

  @override
  void dispose() {
    _periodCtrl.dispose();
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
