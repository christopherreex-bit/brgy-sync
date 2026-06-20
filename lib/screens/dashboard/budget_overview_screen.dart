import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/budget_program_card.dart';

class BudgetOverviewScreen extends StatelessWidget {
  const BudgetOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('budgetPrograms').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];

        double totalAllocated = 0, totalUtilized = 0;
        int flagged = 0;
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          totalAllocated += ((d['allocated'] as num?)?.toDouble() ?? 0);
          totalUtilized += ((d['utilized'] as num?)?.toDouble() ?? 0);
          final status = d['status'] ?? 'healthy';
          if (status == 'low' || status == 'critical') flagged++;
        }
        final totalRemaining = totalAllocated - totalUtilized;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Budget Overview',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 4),
              const Text('Social services budget allocation and utilization.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),

              // Summary row
              Row(
                children: [
                  Expanded(child: KpiCard(label: 'Total Allocated', value: '₱${totalAllocated.toStringAsFixed(0)}', icon: Icons.account_balance)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Utilized', value: '₱${totalUtilized.toStringAsFixed(0)}', accentColor: Colors.orange, icon: Icons.payments)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Remaining', value: '₱${totalRemaining.toStringAsFixed(0)}', accentColor: Colors.green, icon: Icons.savings)),
                  const SizedBox(width: 12),
                  Expanded(child: KpiCard(label: 'Flagged', value: '$flagged', accentColor: flagged > 0 ? Colors.red : Colors.green, icon: Icons.flag)),
                ],
              ),
              const SizedBox(height: 16),

              // Alert banner
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
                  child: Text('$flagged program(s) are below the budget threshold.',
                      style: const TextStyle(fontSize: 13)),
                ),

              const Text('Budget per program',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 12),

              if (docs.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No budget programs configured yet.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ...docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final name = d['name'] ?? '';
                  final status = d['status'] ?? 'healthy';
                  final allocated = (d['allocated'] as num?)?.toDouble() ?? 0;
                  final utilized = (d['utilized'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => context.go('/dashboard/budget/${doc.id}'),
                      child: BudgetProgramCard(
                        programName: name,
                        status: status,
                        allocated: allocated,
                        utilized: utilized,
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
}
