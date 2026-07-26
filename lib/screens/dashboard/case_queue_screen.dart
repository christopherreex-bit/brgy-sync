import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';
import '../../widgets/case_list_item.dart';

class CaseQueueScreen extends StatefulWidget {
  const CaseQueueScreen({super.key});

  @override
  State<CaseQueueScreen> createState() => _CaseQueueScreenState();
}

class _CaseQueueScreenState extends State<CaseQueueScreen> {
  String _activeFilter = 'all';
  final _searchCtrl = TextEditingController();

  static const _statusOrder = {
    'pending_review': 0,
    'processing': 1,
    'awaiting_docs': 2,
    'approved': 3,
    'released': 4,
    'rejected': 5,
  };

  static const _filters = [
    {'key': 'all', 'label': 'All'},
    {'key': 'pending_review', 'label': 'Pending'},
    {'key': 'processing', 'label': 'Processing'},
    {'key': 'awaiting_docs', 'label': 'Awaiting Docs'},
    {'key': 'approved', 'label': 'Approved'},
    {'key': 'released', 'label': 'Released'},
    {'key': 'rejected', 'label': 'Rejected'},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Case Queue',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Active cases monitored against Citizens' Charter deadlines",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Filter tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((f) {
                final isActive = _activeFilter == f['key'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _activeFilter = f['key']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isActive ? kNavy : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive ? kNavy : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        f['label']!,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
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
            onChanged: (_) => setState(() {}),
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
                  child: Text(
                    'CASE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Text(
                  'STATUS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // Case list — simple stream with limit for performance
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _activeFilter == 'all'
                  ? FirebaseFirestore.instance
                        .collection('cases')
                        .orderBy('submissionTimestamp', descending: true)
                        .limit(50)
                        .snapshots()
                  : FirebaseFirestore.instance
                        .collection('cases')
                        .where('status', isEqualTo: _activeFilter)
                        .orderBy('submissionTimestamp', descending: true)
                        .limit(50)
                        .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                var docs = [...?snapshot.data?.docs];

                // Group the queue by workflow stage. Within each stage, show
                // the most recently submitted cases first.
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aStatus =
                      aData['status'] as String? ?? 'pending_review';
                  final bStatus =
                      bData['status'] as String? ?? 'pending_review';
                  final statusComparison = (_statusOrder[aStatus] ?? 999)
                      .compareTo(_statusOrder[bStatus] ?? 999);
                  if (statusComparison != 0) return statusComparison;

                  final aTimestamp = aData['submissionTimestamp'] as Timestamp?;
                  final bTimestamp = bData['submissionTimestamp'] as Timestamp?;
                  return (bTimestamp?.millisecondsSinceEpoch ?? 0).compareTo(
                    aTimestamp?.millisecondsSinceEpoch ?? 0,
                  );
                });

                // Client-side search filter
                final query = _searchCtrl.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final ref = (data['referenceNumber'] ?? '')
                        .toString()
                        .toLowerCase();
                    final name = (data['residentName'] ?? '')
                        .toString()
                        .toLowerCase();
                    final mobile = (data['residentMobile'] ?? '')
                        .toString()
                        .toLowerCase();
                    return ref.contains(query) ||
                        name.contains(query) ||
                        mobile.contains(query);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No cases found',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cases will appear here once residents submit requests.',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final ref = data['referenceNumber'] ?? '';
                    final category = data['serviceCategory'] ?? '';
                    final subType = data['serviceSubType'] ?? '';
                    final status = data['status'] ?? 'pending_review';
                    final isConfidential = data['isConfidential'] ?? false;
                    final residentName = isConfidential
                        ? 'Confidential'
                        : (data['residentName'] ?? '');
                    final ts = data['submissionTimestamp'];
                    final date = ts is Timestamp ? ts.toDate() : DateTime.now();

                    return CaseListItem(
                      referenceNumber: ref,
                      category: category,
                      residentName: residentName,
                      subType: subType,
                      submittedAt: date,
                      status: status,
                      isConfidential: isConfidential,
                      onTap: () =>
                          context.go('/dashboard/case/${docs[index].id}'),
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
