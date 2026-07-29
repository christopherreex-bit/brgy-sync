import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final residentId = context.watch<AuthService>().currentUserModel?.uid;
    if (residentId == null) {
      return const Center(child: Text('Please sign in again.'));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('residentId', isEqualTo: residentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = [...?snapshot.data?.docs];
        docs.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
            aTime?.millisecondsSinceEpoch ?? 0,
          );
        });
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Notifications',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: kNavy,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Status updates and actions required for your cases.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            if (docs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Text('You have no notifications yet.'),
                ),
              )
            else
              ...docs.map((doc) {
                final data = doc.data();
                final unread = data['isRead'] != true;
                final timestamp = data['createdAt'] as Timestamp?;
                final date = timestamp?.toDate();
                return Card(
                  color: unread ? Colors.blue.shade50 : Colors.white,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(
                      data['type'] == 'document_correction'
                          ? Icons.upload_file_outlined
                          : Icons.notifications_outlined,
                      color: unread ? Colors.blue.shade700 : Colors.grey,
                    ),
                    title: Text(
                      (data['title'] ?? 'Case update').toString(),
                      style: TextStyle(
                        fontWeight: unread
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${data['referenceNumber'] ?? ''}\n'
                      '${data['message'] ?? ''}'
                      '${date == null ? '' : '\n${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'}',
                    ),
                    isThreeLine: true,
                    onTap: unread
                        ? () => doc.reference.update({'isRead': true})
                        : null,
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
