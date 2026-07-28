import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

class TrackRequestScreen extends StatelessWidget {
  const TrackRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final residentId = context.watch<AuthService>().currentUserModel?.uid;

    if (residentId == null) {
      return const Center(
        child: Text('Unable to load your cases. Please sign in again.'),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .where('residentId', isEqualTo: residentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _MessageState(
            icon: Icons.error_outline,
            title: 'Could not load your cases',
            message: snapshot.error.toString(),
            color: Colors.red,
          );
        }

        final cases = [...?snapshot.data?.docs];
        cases.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = aData['submissionTimestamp'] as Timestamp?;
          final bDate = bData['submissionTimestamp'] as Timestamp?;
          return (bDate?.millisecondsSinceEpoch ?? 0).compareTo(
            aDate?.millisecondsSinceEpoch ?? 0,
          );
        });

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My Cases',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                cases.isEmpty
                    ? 'Your submitted requests will appear here.'
                    : '${cases.length} ${cases.length == 1 ? 'case' : 'cases'} submitted',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),
              if (cases.isEmpty)
                const _MessageState(
                  icon: Icons.folder_open_outlined,
                  title: 'No cases yet',
                  message:
                      'Submit a request and it will appear here automatically.',
                  color: kNavy,
                )
              else
                ...cases.map(
                  (doc) => _CaseCard(
                    caseId: doc.id,
                    data: doc.data() as Map<String, dynamic>,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CaseCard extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;

  const _CaseCard({required this.caseId, required this.data});

  @override
  Widget build(BuildContext context) {
    final ref = data['referenceNumber'] ?? '';
    final category = data['serviceCategory'] ?? '';
    final subType = data['serviceSubType'] ?? '';
    final status = data['status'] ?? statusPendingReview;
    final assistanceAmount = (data['assistanceAmount'] as num?)?.toDouble();
    final timestamp = data['submissionTimestamp'];
    final submitted = timestamp is Timestamp ? timestamp.toDate() : null;
    final dateText = submitted == null
        ? 'Pending timestamp'
        : '${submitted.month}/${submitted.day}/${submitted.year} '
              '${submitted.hour.toString().padLeft(2, '0')}:'
              '${submitted.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ref,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kNavy,
                    fontSize: 14,
                  ),
                ),
              ),
              StatusBadge(status: status),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _confirmDelete(context, ref.toString()),
                tooltip: 'Delete case',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subType,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _DetailChip(
                icon: Icons.category_outlined,
                label: category.toString().toUpperCase(),
              ),
              _DetailChip(
                icon: Icons.calendar_today_outlined,
                label: 'Submitted $dateText',
              ),
              if (assistanceAmount != null && assistanceAmount > 0)
                _DetailChip(
                  icon: Icons.payments_outlined,
                  label: 'Assistance ₱${_formatAmount(assistanceAmount)}',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              leading: const Icon(Icons.history, color: kNavy, size: 20),
              title: const Text(
                'Status history',
                style: TextStyle(
                  color: kNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                _StatusHistory(
                  caseId: caseId,
                  initialStatus: status.toString(),
                  submittedAt: submitted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$grouped.${parts.last}';
  }

  Future<void> _confirmDelete(BuildContext context, String reference) async {
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
                'Permanently delete $reference and its action log? '
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
    if (deletionReason == null || !context.mounted) return;

    try {
      final user = context.read<AuthService>().currentUserModel;
      if (user == null) throw StateError('Please sign in again.');
      await FirestoreService().deleteCase(
        caseId,
        actorId: user.uid,
        actorName: user.name,
        actorRole: user.role,
        source: 'resident_my_cases',
        deletionReason: deletionReason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$reference was deleted.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete case: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _StatusHistory extends StatelessWidget {
  final String caseId;
  final String initialStatus;
  final DateTime? submittedAt;

  const _StatusHistory({
    required this.caseId,
    required this.initialStatus,
    required this.submittedAt,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('actionLog')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Could not load status history.',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          );
        }

        final logs = [...?snapshot.data?.docs]
            .map((doc) => doc.data() as Map<String, dynamic>)
            .where((log) => (log['newStatus'] ?? '').toString().isNotEmpty)
            .toList();
        logs.sort((a, b) {
          final aTimestamp = a['timestamp'] as Timestamp?;
          final bTimestamp = b['timestamp'] as Timestamp?;
          return (aTimestamp?.millisecondsSinceEpoch ?? 0).compareTo(
            bTimestamp?.millisecondsSinceEpoch ?? 0,
          );
        });

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _StatusHistoryEntry(
                status: logs.isEmpty
                    ? initialStatus
                    : (logs.first['previousStatus'] ?? statusPendingReview)
                          .toString(),
                timestamp: submittedAt,
                note: 'Request submitted',
                isLast: logs.isEmpty,
              ),
              ...logs.asMap().entries.map((entry) {
                final log = entry.value;
                final timestamp = log['timestamp'] is Timestamp
                    ? (log['timestamp'] as Timestamp).toDate()
                    : null;
                return _StatusHistoryEntry(
                  status: log['newStatus'].toString(),
                  timestamp: timestamp,
                  note: (log['notes'] ?? '').toString().trim(),
                  isLast: entry.key == logs.length - 1,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _StatusHistoryEntry extends StatelessWidget {
  final String status;
  final DateTime? timestamp;
  final String note;
  final bool isLast;

  const _StatusHistoryEntry({
    required this.status,
    required this.timestamp,
    required this.note,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = timestamp == null
        ? 'Timestamp pending'
        : '${timestamp!.month}/${timestamp!.day}/${timestamp!.year} '
              '${timestamp!.hour.toString().padLeft(2, '0')}:'
              '${timestamp!.minute.toString().padLeft(2, '0')}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: kNavy,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Colors.grey.shade300),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(status: status),
                  const SizedBox(height: 4),
                  Text(
                    dateText,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        note,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade600),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: kNavy,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
