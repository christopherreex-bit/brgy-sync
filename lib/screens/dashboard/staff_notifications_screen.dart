import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class StaffNotificationsScreen extends StatelessWidget {
  const StaffNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUserModel;
    if (user == null) return const Center(child: Text('Please sign in again.'));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('staffNotifications')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load notifications: ${snapshot.error}'),
          );
        }
        final docs =
            [...?snapshot.data?.docs].where((doc) {
              final data = doc.data();
              final recipientId = (data['recipientId'] ?? '').toString();
              final targetRoles = List<String>.from(data['targetRoles'] ?? []);
              return recipientId == user.uid || targetRoles.contains(user.role);
            }).toList()..sort((a, b) {
              final aTime = a.data()['createdAt'] as Timestamp?;
              final bTime = b.data()['createdAt'] as Timestamp?;
              return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
                aTime?.millisecondsSinceEpoch ?? 0,
              );
            });
        final unread = docs
            .where(
              (doc) => !List<String>.from(
                doc.data()['readBy'] ?? [],
              ).contains(user.uid),
            )
            .toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: kNavy,
                          ),
                        ),
                        Text(
                          'SLA reminders, escalations, and operational alerts.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (unread.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _markAllRead(unread, user.uid),
                      icon: const Icon(Icons.done_all),
                      label: const Text('Mark all as read'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: docs.isEmpty
                    ? const Center(child: Text('No notifications yet.'))
                    : ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final readBy = List<String>.from(
                            data['readBy'] ?? [],
                          );
                          final isUnread = !readBy.contains(user.uid);
                          final urgent = data['priority'] == 'urgent';
                          final timestamp = data['createdAt'] as Timestamp?;
                          final date = timestamp?.toDate();
                          return Card(
                            color: isUnread
                                ? urgent
                                      ? Colors.red.shade50
                                      : Colors.blue.shade50
                                : Colors.white,
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: urgent
                                    ? Colors.red.shade100
                                    : Colors.blue.shade100,
                                child: Icon(
                                  _iconFor(data['type']?.toString()),
                                  color: urgent
                                      ? Colors.red.shade700
                                      : Colors.blue.shade700,
                                ),
                              ),
                              title: Text(
                                (data['title'] ?? 'Notification').toString(),
                                style: TextStyle(
                                  fontWeight: isUnread
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                '${data['message'] ?? ''}'
                                '${date == null ? '' : '\n${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'}',
                              ),
                              isThreeLine: date != null,
                              trailing: isUnread
                                  ? const Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: Colors.blue,
                                    )
                                  : null,
                              onTap: () async {
                                if (isUnread) {
                                  await doc.reference.update({
                                    'readBy': FieldValue.arrayUnion([user.uid]),
                                  });
                                }
                                final caseId = (data['caseId'] ?? '')
                                    .toString();
                                if (caseId.isNotEmpty && context.mounted) {
                                  context.go('/dashboard/case/$caseId');
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _markAllRead(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
  ) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      batch.update(doc.reference, {
        'readBy': FieldValue.arrayUnion([uid]),
      });
    }
    await batch.commit();
  }

  static IconData _iconFor(String? type) => switch (type) {
    'sla_reminder' => Icons.timer_outlined,
    'correction_escalation' => Icons.upload_file_outlined,
    'captain_digest' => Icons.summarize_outlined,
    'budget_alert' => Icons.account_balance_wallet_outlined,
    'case_assignment' => Icons.assignment_ind_outlined,
    'claiming_approval' => Icons.approval_outlined,
    _ => Icons.notifications_outlined,
  };
}
