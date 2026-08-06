import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/case_list_item.dart';

class CaseQueueScreen extends StatefulWidget {
  const CaseQueueScreen({super.key});

  @override
  State<CaseQueueScreen> createState() => _CaseQueueScreenState();
}

class _CaseQueueScreenState extends State<CaseQueueScreen> {
  String _activeFilter = 'all';
  String _queueScope = 'all';
  String _assigneeFilter = 'all';
  final _searchCtrl = TextEditingController();

  static const _statusOrder = {
    'pending_review': 0,
    'processing': 1,
    'awaiting_docs': 2,
    'approved': 3,
    'for_claiming': 4,
    'released': 5,
    'rejected': 6,
  };

  static const _baseFilters = [
    {'key': 'all', 'label': 'All'},
    {'key': 'pending_review', 'label': 'Pending Review'},
    {'key': 'processing', 'label': 'Processing'},
    {'key': 'approved', 'label': 'Approved'},
    {'key': 'for_claiming', 'label': 'For Claiming'},
    {'key': 'released', 'label': 'Released'},
    {'key': 'rejected', 'label': 'Rejected'},
  ];

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthService>().currentUserModel;
    final canDelete = currentUser?.role == roleCaptain;
    final Query<Map<String, dynamic>> caseQuery;
    if (_queueScope == 'claiming_approval') {
      caseQuery = FirebaseFirestore.instance
          .collection('cases')
          .where('claimingApprovalStatus', isEqualTo: 'pending');
    } else if (_activeFilter == 'all' || _activeFilter == statusPendingReview) {
      caseQuery = FirebaseFirestore.instance
          .collection('cases')
          .orderBy('submissionTimestamp', descending: true)
          .limit(50);
    } else {
      caseQuery = FirebaseFirestore.instance
          .collection('cases')
          .where('status', isEqualTo: _activeFilter)
          .orderBy('submissionTimestamp', descending: true)
          .limit(50);
    }

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
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              final assignees =
                  [...?snapshot.data?.docs].where((doc) {
                    final data = doc.data();
                    return data['isActive'] != false &&
                        [roleStaff, roleOfficer].contains(data['role']);
                  }).toList()..sort(
                    (a, b) => (a.data()['name'] ?? '').toString().compareTo(
                      (b.data()['name'] ?? '').toString(),
                    ),
                  );
              final scopes = [
                const {'key': 'all', 'label': 'All Cases'},
                const {'key': 'assigned_to_me', 'label': 'Assigned to Me'},
                const {'key': 'unassigned', 'label': 'Unassigned'},
                if (canDelete)
                  const {
                    'key': 'claiming_approval',
                    'label': 'Claiming Approvals',
                  },
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _activeFilter,
                      decoration: const InputDecoration(
                        labelText: 'Case status',
                        prefixIcon: Icon(Icons.filter_alt_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _baseFilters
                          .map(
                            (filter) => DropdownMenuItem(
                              value: filter['key'],
                              child: Text(filter['label']!),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _activeFilter = value ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<String>(
                      initialValue: _queueScope,
                      decoration: const InputDecoration(
                        labelText: 'Queue view',
                        prefixIcon: Icon(Icons.view_list_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: scopes
                          .map(
                            (scope) => DropdownMenuItem(
                              value: scope['key'],
                              child: Text(scope['label']!),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _queueScope = value ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 290,
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          _assigneeFilter == 'all' ||
                              assignees.any((doc) => doc.id == _assigneeFilter)
                          ? _assigneeFilter
                          : 'all',
                      decoration: const InputDecoration(
                        labelText: 'Assigned officer/staff',
                        prefixIcon: Icon(Icons.person_search_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All assignees'),
                        ),
                        ...assignees.map(
                          (doc) => DropdownMenuItem(
                            value: doc.id,
                            child: Text((doc.data()['name'] ?? '').toString()),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _assigneeFilter = value ?? 'all'),
                    ),
                  ),
                ],
              );
            },
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
              stream: caseQuery.snapshots(),
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
                if (_activeFilter == statusPendingReview) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return normalizeCaseStatus(
                          (data['status'] ?? statusPendingReview).toString(),
                        ) ==
                        statusPendingReview;
                  }).toList();
                }
                if (_queueScope == 'claiming_approval') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['status'] == statusApproved &&
                        data['claimingApprovalStatus'] == 'pending';
                  }).toList();
                }
                if (_assigneeFilter != 'all') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['assignedStaffId'] == _assigneeFilter;
                  }).toList();
                }
                if (_queueScope == 'assigned_to_me') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['assignedStaffId'] == currentUser?.uid;
                  }).toList();
                } else if (_queueScope == 'unassigned') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return (data['assignedStaffId'] ?? '').toString().isEmpty;
                  }).toList();
                }

                // Group the queue by workflow stage. Within each stage, show
                // the most recently submitted cases first.
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aStatus = normalizeCaseStatus(
                    aData['status'] as String? ?? statusPendingReview,
                  );
                  final bStatus = normalizeCaseStatus(
                    bData['status'] as String? ?? statusPendingReview,
                  );
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
                    final status = normalizeCaseStatus(
                      (data['status'] ?? statusPendingReview).toString(),
                    );
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
                      awaitingCaptainApproval:
                          data['claimingApprovalStatus'] == 'pending',
                      claimingApprovalRejected:
                          data['claimingApprovalStatus'] == 'rejected',
                      claimingRejectionReason:
                          (data['claimingRejectionReason'] ?? '').toString(),
                      claimingRejectedByName:
                          (data['claimingRejectedByName'] ?? '').toString(),
                      assignedStaffName: (data['assignedStaffName'] ?? '')
                          .toString(),
                      onTap: () =>
                          context.go('/dashboard/case/${docs[index].id}'),
                      onDelete: canDelete
                          ? () => _confirmDeleteCase(
                              docs[index].id,
                              ref.toString(),
                            )
                          : null,
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

  Future<void> _confirmDeleteCase(String caseId, String referenceNumber) async {
    final reasonController = TextEditingController();
    String? reasonError;
    final deletionReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete case?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permanently delete $referenceNumber and its action log? '
                'Any recorded budget deduction will be reversed.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason for deletion *',
                  border: const OutlineInputBorder(),
                  errorText: reasonError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  setDialogState(
                    () => reasonError = 'Please enter a reason for deletion.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, reason);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (deletionReason == null || !mounted) return;

    try {
      final user = context.read<AuthService>().currentUserModel;
      if (user == null || !user.isCaptain) {
        throw StateError('Only the Barangay Captain can delete cases.');
      }
      await FirestoreService().deleteCase(
        caseId,
        actorId: user.uid,
        actorName: user.name,
        actorRole: user.role,
        source: 'captain_case_queue',
        deletionReason: deletionReason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$referenceNumber was deleted.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete case: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
