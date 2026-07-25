import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';
import '../../services/auth_service.dart';

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
                  (doc) => _CaseCard(data: doc.data() as Map<String, dynamic>),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CaseCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _CaseCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final ref = data['referenceNumber'] ?? '';
    final category = data['serviceCategory'] ?? '';
    final subType = data['serviceSubType'] ?? '';
    final status = data['status'] ?? statusPendingReview;
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
            ],
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
