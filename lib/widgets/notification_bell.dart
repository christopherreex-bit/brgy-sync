import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

class NotificationBell extends StatelessWidget {
  final Color iconColor;
  final VoidCallback? onResidentCasesRequested;

  const NotificationBell({
    super.key,
    this.iconColor = Colors.white,
    this.onResidentCasesRequested,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUserModel;
    if (user == null) return const SizedBox.shrink();
    return _NotificationStreams(
      user: user,
      builder: (notifications) {
        final visibleNotifications = notifications
            .where((item) => !item.deletedBy.contains(user.uid))
            .toList();
        final unread = visibleNotifications
            .where((item) => !item.readBy.contains(user.uid))
            .length;
        return IconButton(
          tooltip: unread == 0
              ? 'Notifications'
              : '$unread unread notifications',
          onPressed: () =>
              _showNotifications(context, user, visibleNotifications),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(Icons.notifications_outlined, color: iconColor),
          ),
        );
      },
    );
  }

  Future<void> _showNotifications(
    BuildContext context,
    UserModel user,
    List<_NotificationItem> notifications,
  ) async {
    var selectionMode = false;
    final selectedIds = <String>{};

    Future<void> updateSelected({
      required String field,
      required bool add,
    }) async {
      final selected = notifications
          .where((item) => selectedIds.contains(item.reference.id))
          .toList();
      if (selected.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final item in selected) {
        batch.update(item.reference, {
          field: add
              ? FieldValue.arrayUnion([user.uid])
              : FieldValue.arrayRemove([user.uid]),
        });
      }
      await batch.commit();
      for (final item in selected) {
        final values = field == 'readBy' ? item.readBy : item.deletedBy;
        if (add) {
          if (!values.contains(user.uid)) values.add(user.uid);
        } else {
          values.remove(user.uid);
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = notifications
              .where((item) => !item.deletedBy.contains(user.uid))
              .toList();
          final allSelected =
              visible.isNotEmpty && selectedIds.length == visible.length;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.notifications_outlined, color: kNavy),
                const SizedBox(width: 10),
                const Expanded(child: Text('Notifications')),
                if (selectionMode) ...[
                  TextButton(
                    onPressed: visible.isEmpty
                        ? null
                        : () {
                            setDialogState(() {
                              if (allSelected) {
                                selectedIds.clear();
                              } else {
                                selectedIds
                                  ..clear()
                                  ..addAll(
                                    visible.map((item) => item.reference.id),
                                  );
                              }
                            });
                          },
                    child: Text(allSelected ? 'Clear all' : 'Select all'),
                  ),
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        selectionMode = false;
                        selectedIds.clear();
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                ] else
                  TextButton.icon(
                    onPressed: visible.isEmpty
                        ? null
                        : () => setDialogState(() => selectionMode = true),
                    icon: const Icon(Icons.checklist, size: 18),
                    label: const Text('Select'),
                  ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 520,
              child: visible.isEmpty
                  ? const Center(child: Text('No notifications yet.'))
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final isUnread = !item.readBy.contains(user.uid);
                        final isSelected = selectedIds.contains(
                          item.reference.id,
                        );
                        return Material(
                          color: isUnread
                              ? Colors.blue.shade50
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              if (selectionMode) {
                                setDialogState(() {
                                  if (isSelected) {
                                    selectedIds.remove(item.reference.id);
                                  } else {
                                    selectedIds.add(item.reference.id);
                                  }
                                });
                                return;
                              }
                              if (isUnread) {
                                await item.reference.update({
                                  'readBy': FieldValue.arrayUnion([user.uid]),
                                });
                                item.readBy.add(user.uid);
                                setDialogState(() {});
                              }
                              if (!user.isResident && item.caseId.isNotEmpty) {
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                  context.push(
                                    '/dashboard/case/${item.caseId}',
                                  );
                                }
                              } else if (user.isResident &&
                                  item.caseId.isNotEmpty &&
                                  onResidentCasesRequested != null) {
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                  onResidentCasesRequested!();
                                }
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (selectionMode) ...[
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (_) {
                                        setDialogState(() {
                                          if (isSelected) {
                                            selectedIds.remove(
                                              item.reference.id,
                                            );
                                          } else {
                                            selectedIds.add(item.reference.id);
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  CircleAvatar(
                                    radius: 19,
                                    backgroundColor: _typeColor(
                                      item.type,
                                    ).withValues(alpha: .12),
                                    child: Icon(
                                      _typeIcon(item.type),
                                      size: 20,
                                      color: _typeColor(item.type),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: TextStyle(
                                            fontWeight: isUnread
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.message,
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _timeLabel(item.createdAt),
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isUnread)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 5),
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              if (selectionMode && selectedIds.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () async {
                    await updateSelected(field: 'readBy', add: true);
                    setDialogState(() {
                      selectedIds.clear();
                      selectionMode = false;
                    });
                  },
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: const Text('Mark as read'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await updateSelected(field: 'readBy', add: false);
                    setDialogState(() {
                      selectedIds.clear();
                      selectionMode = false;
                    });
                  },
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Mark as unread'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await updateSelected(field: 'deletedBy', add: true);
                    setDialogState(() {
                      selectedIds.clear();
                      selectionMode = false;
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  static IconData _typeIcon(String type) => switch (type) {
    'case_submitted' => Icons.note_add_outlined,
    'claiming_approval' => Icons.approval_outlined,
    'needs_correction' => Icons.edit_note_outlined,
    'case_rejected' => Icons.cancel_outlined,
    'case_released' => Icons.payments_outlined,
    _ => Icons.info_outline,
  };

  static Color _typeColor(String type) => switch (type) {
    'needs_correction' || 'claiming_approval' => Colors.orange.shade800,
    'case_rejected' => Colors.red.shade700,
    'case_released' => Colors.green.shade700,
    _ => kNavy,
  };

  static String _timeLabel(DateTime? value) => value == null
      ? 'Just now'
      : DateFormat('MMM d, yyyy · h:mm a').format(value);
}

class _NotificationStreams extends StatelessWidget {
  final UserModel user;
  final Widget Function(List<_NotificationItem>) builder;

  const _NotificationStreams({required this.user, required this.builder});

  @override
  Widget build(BuildContext context) {
    final direct = FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientId', isEqualTo: user.uid)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: direct,
      builder: (context, directSnapshot) {
        if (user.isResident) {
          return builder(
            _merge(directSnapshot.data?.docs ?? const [], const []),
          );
        }
        final audience = FirebaseFirestore.instance
            .collection('notifications')
            .where('audienceRoles', arrayContains: user.effectiveRole)
            .snapshots();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: audience,
          builder: (context, audienceSnapshot) => builder(
            _merge(
              directSnapshot.data?.docs ?? const [],
              audienceSnapshot.data?.docs ?? const [],
            ),
          ),
        );
      },
    );
  }

  List<_NotificationItem> _merge(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> direct,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> audience,
  ) {
    final byId = <String, _NotificationItem>{};
    for (final doc in [...direct, ...audience]) {
      byId[doc.id] = _NotificationItem.fromDocument(doc);
    }
    final result = byId.values.toList()
      ..sort(
        (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
          a.createdAt ?? DateTime(1970),
        ),
      );
    return result;
  }
}

class _NotificationItem {
  final DocumentReference<Map<String, dynamic>> reference;
  final String title;
  final String message;
  final String type;
  final String caseId;
  final DateTime? createdAt;
  final List<String> readBy;
  final List<String> deletedBy;

  _NotificationItem({
    required this.reference,
    required this.title,
    required this.message,
    required this.type,
    required this.caseId,
    required this.createdAt,
    required this.readBy,
    required this.deletedBy,
  });

  factory _NotificationItem.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return _NotificationItem(
      reference: document.reference,
      title: (data['title'] ?? 'Notification').toString(),
      message: (data['message'] ?? '').toString(),
      type: (data['type'] ?? '').toString(),
      caseId: (data['caseId'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      readBy: List<String>.from(data['readBy'] ?? const []),
      deletedBy: List<String>.from(data['deletedBy'] ?? const []),
    );
  }
}
