import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../models/service_category.dart';
import '../../widgets/case_list_item.dart';

class CaseQueueScreen extends StatefulWidget {
  const CaseQueueScreen({super.key});

  @override
  State<CaseQueueScreen> createState() => _CaseQueueScreenState();
}

class _CaseQueueScreenState extends State<CaseQueueScreen> {
  String _activeFilter = 'all';
  final _searchCtrl = TextEditingController();
  String _categoryFilter = 'all';
  String _dateFilter = 'all';
  String _sortOrder = 'fifo';

  bool get _hasAdvancedFilters =>
      _activeFilter != 'all' ||
      _categoryFilter != 'all' ||
      _dateFilter != 'all';

  static const _baseFilters = [
    {'key': 'all', 'label': 'All statuses'},
    {'key': 'pending_review', 'label': 'Pending Review'},
    {'key': 'processing', 'label': 'Processing'},
    {'key': 'approved', 'label': 'Approved'},
    {'key': 'for_claiming', 'label': 'For Claiming'},
    {'key': 'released', 'label': 'Released'},
    {'key': 'rejected', 'label': 'Rejected'},
  ];

  static String _normalizeSearchValue(Object? value) {
    return (value ?? '')
        .toString()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static bool _matchesCaseSearch(Map<String, dynamic> data, String rawQuery) {
    final tokens = _normalizeSearchValue(
      rawQuery,
    ).split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();
    if (tokens.isEmpty) return true;

    // Search only resident/case information that identifies the row. Hidden
    // workflow metadata (encoder, assigned staff, requester) is intentionally
    // excluded because it produced visually unrelated results.
    final searchableText = _normalizeSearchValue(
      [
        data['referenceNumber'],
        data['residentName'],
        data['residentMobile'],
        data['residentAddress'],
        data['serviceCategory'],
        data['serviceSubType'],
        normalizeCaseStatus((data['status'] ?? '').toString()),
        data['submissionChannel'],
      ].whereType<Object>().join(' '),
    );

    return tokens.every(searchableText.contains);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthService>().currentUserModel;
    final canDelete = currentUser?.role == roleCaptain;
    final filters = [
      ..._baseFilters,
      if (canDelete)
        const {'key': 'claiming_approval', 'label': 'Claiming Approvals'},
    ];
    final Query<Map<String, dynamic>> caseQuery;
    if (_activeFilter == 'claiming_approval') {
      caseQuery = FirebaseFirestore.instance
          .collection('cases')
          .where('claimingApprovalStatus', isEqualTo: 'pending');
    } else if (_activeFilter == 'all' || _activeFilter == statusPendingReview) {
      caseQuery = FirebaseFirestore.instance
          .collection('cases')
          .orderBy('submissionTimestamp', descending: true);
    } else {
      caseQuery = FirebaseFirestore.instance
          .collection('cases')
          .where('status', isEqualTo: _activeFilter)
          .orderBy('submissionTimestamp', descending: true);
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
              hintText:
                  'Search cases using any combination of name, phone, reference, service, or status',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
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

          // Uniform dropdown filters keep the queue compact and predictable.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _queueDropdown(
                label: 'Status',
                value: _activeFilter,
                width: 180,
                items: filters
                    .map(
                      (filter) => DropdownMenuItem(
                        value: filter['key'],
                        child: Text(filter['label']!),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _activeFilter = value ?? 'all';
                }),
              ),
              _queueDropdown(
                label: 'Category',
                value: _categoryFilter,
                width: 180,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All categories'),
                  ),
                  ...kServiceCategories.map(
                    (category) => DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _categoryFilter = value ?? 'all';
                }),
              ),
              _queueDropdown(
                label: 'Submitted',
                value: _dateFilter,
                width: 160,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Any time')),
                  DropdownMenuItem(value: '7', child: Text('Last 7 days')),
                  DropdownMenuItem(value: '30', child: Text('Last 30 days')),
                  DropdownMenuItem(value: '90', child: Text('Last 90 days')),
                ],
                onChanged: (value) => setState(() {
                  _dateFilter = value ?? 'all';
                }),
              ),
              _queueDropdown(
                label: 'Sort by',
                value: _sortOrder,
                width: 210,
                items: const [
                  DropdownMenuItem(
                    value: 'fifo',
                    child: Text('FIFO — oldest submitted'),
                  ),
                  DropdownMenuItem(
                    value: 'longest_status',
                    child: Text('Longest in current status'),
                  ),
                  DropdownMenuItem(
                    value: 'recent_status',
                    child: Text('Recently changed status'),
                  ),
                  DropdownMenuItem(
                    value: 'newest',
                    child: Text('Newest submitted'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _sortOrder = value ?? 'fifo';
                }),
              ),
              if (_hasAdvancedFilters)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _activeFilter = 'all';
                    _categoryFilter = 'all';
                    _dateFilter = 'all';
                  }),
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear filters'),
                ),
            ],
          ),
          const SizedBox(height: 12),

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
                if (_activeFilter == 'claiming_approval') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['status'] == statusApproved &&
                        data['claimingApprovalStatus'] == 'pending';
                  }).toList();
                }

                // FIFO queue: all unfinished cases come first, from oldest to
                // newest. Completed cases remain available for reference but
                // are moved to the end of the queue.
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aStatus = normalizeCaseStatus(
                    aData['status'] as String? ?? statusPendingReview,
                  );
                  final bStatus = normalizeCaseStatus(
                    bData['status'] as String? ?? statusPendingReview,
                  );
                  final aFinished =
                      aStatus == statusReleased || aStatus == statusRejected;
                  final bFinished =
                      bStatus == statusReleased || bStatus == statusRejected;
                  if (aFinished != bFinished) return aFinished ? 1 : -1;

                  final aSubmitted =
                      (aData['submissionTimestamp'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  final bSubmitted =
                      (bData['submissionTimestamp'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  final aStatusUpdated =
                      (aData['statusUpdatedAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      aSubmitted;
                  final bStatusUpdated =
                      (bData['statusUpdatedAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      bSubmitted;

                  final comparison = switch (_sortOrder) {
                    'longest_status' => aStatusUpdated.compareTo(
                      bStatusUpdated,
                    ),
                    'recent_status' => bStatusUpdated.compareTo(aStatusUpdated),
                    'newest' => bSubmitted.compareTo(aSubmitted),
                    _ => aSubmitted.compareTo(bSubmitted),
                  };
                  if (comparison != 0) return comparison;
                  return aSubmitted.compareTo(bSubmitted);
                });

                // Client-side search filter
                final searchQuery = _searchCtrl.text.trim();
                if (searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _matchesCaseSearch(data, searchQuery);
                  }).toList();
                }

                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (_categoryFilter != 'all' &&
                      data['serviceCategory'] != _categoryFilter) {
                    return false;
                  }
                  if (_dateFilter != 'all') {
                    final timestamp = data['submissionTimestamp'];
                    if (timestamp is! Timestamp) return false;
                    final days = int.tryParse(_dateFilter) ?? 0;
                    final cutoff = DateTime.now().subtract(
                      Duration(days: days),
                    );
                    if (timestamp.toDate().isBefore(cutoff)) return false;
                  }
                  return true;
                }).toList();

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

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          docs.length == 1
                              ? '1 case shown'
                              : '${docs.length} cases shown',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final ref = data['referenceNumber'] ?? '';
                          final category = data['serviceCategory'] ?? '';
                          final subType = data['serviceSubType'] ?? '';
                          final status = normalizeCaseStatus(
                            (data['status'] ?? statusPendingReview).toString(),
                          );
                          final isConfidential =
                              data['isConfidential'] ?? false;
                          final residentName = isConfidential
                              ? 'Confidential'
                              : (data['residentName'] ?? '');
                          final ts = data['submissionTimestamp'];
                          final date = ts is Timestamp
                              ? ts.toDate()
                              : DateTime.now();

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
                                (data['claimingRejectionReason'] ?? '')
                                    .toString(),
                            claimingRejectedByName:
                                (data['claimingRejectedByName'] ?? '')
                                    .toString(),
                            onTap: () =>
                                context.go('/dashboard/case/${doc.id}'),
                            onDelete: canDelete
                                ? () =>
                                      _confirmDeleteCase(doc.id, ref.toString())
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueDropdown({
    required String label,
    required String value,
    required double width,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: items,
        onChanged: onChanged,
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
