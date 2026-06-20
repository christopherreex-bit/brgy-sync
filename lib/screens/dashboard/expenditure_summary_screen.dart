import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';

class ExpenditureSummaryScreen extends StatefulWidget {
  const ExpenditureSummaryScreen({super.key});

  @override
  State<ExpenditureSummaryScreen> createState() => _ExpenditureSummaryScreenState();
}

class _ExpenditureSummaryScreenState extends State<ExpenditureSummaryScreen> {
  String _selectedPeriod = 'All Periods';
  String _selectedCategory = 'All Categories';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Expenditure Summary',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Budget expenditure breakdown by program and period.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),

          // Filters
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedPeriod,
                  decoration: const InputDecoration(
                    labelText: 'Period',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: ['All Periods', 'FY 2026', 'FY 2025']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedPeriod = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: ['All Categories', 'BASS', 'Senior Citizen', 'PWD', 'Education']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Breakdown table
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('budgetPrograms').snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              double totalAllocated = 0, totalUtilized = 0, totalRemaining = 0;

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
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text('Program', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('Allocated', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('Utilized', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('Remaining', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                    ),
                    if (docs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No data available.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...docs.map((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        final allocated = (d['allocated'] as num?)?.toDouble() ?? 0;
                        final utilized = (d['utilized'] as num?)?.toDouble() ?? 0;
                        final remaining = allocated - utilized;
                        totalAllocated += allocated;
                        totalUtilized += utilized;
                        totalRemaining += remaining;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text(d['name'] ?? '', style: const TextStyle(fontSize: 12))),
                              Expanded(child: Text('₱${allocated.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12))),
                              Expanded(child: Text('₱${utilized.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12))),
                              Expanded(child: Text('₱${remaining.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        );
                      }),
                    // Totals row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(flex: 3, child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('₱${totalAllocated.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('₱${totalUtilized.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('₱${totalRemaining.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export to Excel — coming soon'))),
                icon: const Icon(Icons.download),
                label: const Text('Export (.xlsx)'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print PDF — coming soon'))),
                icon: const Icon(Icons.print),
                label: const Text('Print PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
