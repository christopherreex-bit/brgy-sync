import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';

class ServiceDemandScreen extends StatefulWidget {
  const ServiceDemandScreen({super.key});

  @override
  State<ServiceDemandScreen> createState() => _ServiceDemandScreenState();
}

class _ServiceDemandScreenState extends State<ServiceDemandScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Service Demand Statistics',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Descriptive statistics by service category.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),

          // Time filter tabs
          Row(
            children: [
              _filterBtn('All Time', 'all'),
              const SizedBox(width: 8),
              _filterBtn('This Month', 'month'),
              const SizedBox(width: 8),
              _filterBtn('Last 3 Months', '3months'),
              const SizedBox(width: 8),
              _filterBtn('Year to Date', 'ytd'),
            ],
          ),
          const SizedBox(height: 20),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('cases').snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final categoryStats = <String, Map<String, int>>{};
              int total = 0;

              for (final doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final cat = data['serviceCategory'] ?? 'unknown';
                final status = data['status'] ?? '';
                categoryStats.putIfAbsent(cat, () => {'requests': 0, 'resolved': 0});
                categoryStats[cat]!['requests'] = categoryStats[cat]!['requests']! + 1;
                total++;
                if (status == 'released') {
                  categoryStats[cat]!['resolved'] = categoryStats[cat]!['resolved']! + 1;
                }
              }

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
                          Expanded(flex: 3, child: Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('% of Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('Resolved', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                    ),
                    if (categoryStats.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No data available.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...categoryStats.entries.map((entry) {
                        final pct = total > 0 ? (entry.value['requests']! / total * 100).toStringAsFixed(1) : '0.0';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text(entry.key.toUpperCase(), style: const TextStyle(fontSize: 12))),
                              Expanded(child: Text('${entry.value['requests']}', style: const TextStyle(fontSize: 12))),
                              Expanded(child: Text('$pct%', style: const TextStyle(fontSize: 12))),
                              Expanded(child: Text('${entry.value['resolved']}', style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterBtn(String label, String key) {
    final isActive = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? kNavy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? kNavy : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: isActive ? Colors.white : Colors.grey.shade700,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}
