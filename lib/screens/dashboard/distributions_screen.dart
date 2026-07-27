import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';

class DistributionsScreen extends StatefulWidget {
  const DistributionsScreen({super.key});

  @override
  State<DistributionsScreen> createState() => _DistributionsScreenState();
}

class _DistributionsScreenState extends State<DistributionsScreen> {
  String _activeTab = 'all';
  final _tabs = const [
    {'key': 'all', 'label': 'All Programs'},
    {'key': 'senior_birthday', 'label': 'Senior Citizen'},
    {'key': 'pwd_birthday', 'label': 'PWD'},
    {'key': 'education_incentive', 'label': 'Education Incentive'},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Distribution Programs',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Manage beneficiary distributions for senior citizens, PWD, and education incentives.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          // Tabs
          Row(
            children: _tabs.map((t) {
              final isActive = _activeTab == t['key'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _activeTab = t['key']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? kNavy : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isActive ? kNavy : Colors.grey.shade300),
                    ),
                    child: Text(t['label']!,
                        style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Content
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _activeTab == 'all'
                  ? FirebaseFirestore.instance.collection('distributions').limit(50).snapshots()
                  : FirebaseFirestore.instance
                      .collection('distributions')
                      .where('programType', isEqualTo: _activeTab)
                      .limit(50)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No distribution records yet.',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Distribution records will appear here once added.',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final name = data['beneficiaryName'] ?? '';
                    final status = data['status'] ?? 'pending';
                    final programType = data['programType'] ?? '';
                    final age = data['age']?.toString() ?? '';
                    final gradeLevel = data['gradeLevel'] ?? '';
                    final school = data['school'] ?? '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: kNavy.withValues(alpha: 0.1),
                            child: Text(
                              name.isNotEmpty ? name.split(' ').map((w) => w[0]).take(2).join() : '?',
                              style: const TextStyle(color: kNavy, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(
                                  programType == 'education_incentive'
                                      ? '$gradeLevel · $school'
                                      : '$programType · Age: $age',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(status: status),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
