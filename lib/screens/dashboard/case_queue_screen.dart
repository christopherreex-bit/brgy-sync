import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class CaseQueueScreen extends StatefulWidget {
  const CaseQueueScreen({super.key});

  @override
  State<CaseQueueScreen> createState() => _CaseQueueScreenState();
}

class _CaseQueueScreenState extends State<CaseQueueScreen> {
  String _activeFilter = 'all';
  final _searchCtrl = TextEditingController();

  static const _filters = [
    'All', 'Pending', 'Processing', 'Awaiting Docs', 'Approved', 'Resolved',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Case Queue',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Active cases monitored against Citizens\' Charter deadlines',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          // Filter tabs
          Row(
            children: _filters.map((f) {
              final isActive = _activeFilter == f.toLowerCase().replaceAll(' ', '_');
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _activeFilter = f.toLowerCase().replaceAll(' ', '_')),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? kNavy : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isActive ? kNavy : Colors.grey.shade300),
                    ),
                    child: Text(f,
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
          // Search bar
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by name, reference number, or contact',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 16),
          // Case list header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text('CASE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                ),
                Text('STATUS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          // Case list (placeholder)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No cases yet',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Cases will appear here once residents submit requests.',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
