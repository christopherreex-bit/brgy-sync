import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class DelegationHistoryScreen extends StatelessWidget {
  const DelegationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUserModel;
    if (user?.isPermanentCaptain != true) {
      return const Center(
        child: Text(
          'Delegation history is restricted to the permanent captain.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delegation of Authority History',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Grants, duration changes, revocations, and actions performed while acting as Barangay Captain.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: FutureBuilder<List<_DelegationHistoryItem>>(
              future: _loadHistory(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load delegation history: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No delegation history recorded yet.'),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: item.isAuthorityEvent
                              ? Colors.orange.shade100
                              : Colors.blue.shade100,
                          child: Icon(
                            item.isAuthorityEvent
                                ? Icons.admin_panel_settings_outlined
                                : Icons.history,
                            color: item.isAuthorityEvent
                                ? Colors.orange.shade900
                                : kNavy,
                          ),
                        ),
                        title: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          [
                            item.actorName,
                            DateFormat('MMM d, yyyy h:mm a').format(item.at),
                            if (item.details.isNotEmpty) item.details,
                          ].where((value) => value.isNotEmpty).join(' · '),
                        ),
                        trailing: Chip(
                          label: Text(
                            item.isAuthorityEvent
                                ? 'AUTHORITY'
                                : 'ACTING ACTION',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
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

  Future<List<_DelegationHistoryItem>> _loadHistory() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('captainDelegationEvents').get(),
      db.collectionGroup('actionLog').limit(800).get(),
      db.collection('cashMovements').limit(500).get(),
      db.collection('distributions').limit(500).get(),
      db.collection('auditEvents').limit(500).get(),
    ]);
    final eventDocs = results[0].docs;
    final intervals = <String, List<_AuthorityInterval>>{};
    final chronologicalEvents = [...eventDocs]
      ..sort(
        (a, b) => _time(
          a.data(),
          'createdAt',
          fallback: 'startsAt',
        ).compareTo(_time(b.data(), 'createdAt', fallback: 'startsAt')),
      );
    final items = <_DelegationHistoryItem>[];
    for (final document in chronologicalEvents) {
      final data = document.data();
      final type = (data['eventType'] ?? '').toString();
      final uid = (data['delegateUid'] ?? '').toString();
      final name = (data['delegateName'] ?? 'Acting captain').toString();
      final at = _time(data, 'createdAt', fallback: 'startsAt');
      if (type == 'granted' && uid.isNotEmpty) {
        (intervals[uid] ??= []).add(
          _AuthorityInterval(
            start: _time(data, 'startsAt'),
            end: _time(data, 'expiresAt'),
          ),
        );
      } else if (type == 'duration_changed' && uid.isNotEmpty) {
        final list = intervals[uid];
        if (list != null && list.isNotEmpty) {
          list.last.end = _time(data, 'expiresAt');
        }
      } else if (type == 'revoked' && uid.isNotEmpty) {
        final list = intervals[uid];
        if (list != null && list.isNotEmpty && at.isBefore(list.last.end)) {
          list.last.end = at;
        }
      }
      items.add(
        _DelegationHistoryItem(
          at: at,
          actorName: name,
          title: switch (type) {
            'granted' => 'Temporary authority granted',
            'duration_changed' => 'Delegation duration changed',
            'revoked' => 'Temporary authority revoked',
            _ => 'Delegation updated',
          },
          details: (data['reason'] ?? '').toString(),
          isAuthorityEvent: true,
        ),
      );
    }

    void addActingAction(
      Map<String, dynamic> data, {
      required String uidField,
      required String nameField,
      required String timeField,
      required String title,
      String detailsField = 'reason',
    }) {
      final uid = (data[uidField] ?? '').toString();
      final timestamp = _time(data, timeField);
      final authorized =
          intervals[uid]?.any(
            (interval) =>
                !timestamp.isBefore(interval.start) &&
                timestamp.isBefore(interval.end),
          ) ??
          false;
      if (!authorized) return;
      items.add(
        _DelegationHistoryItem(
          at: timestamp,
          actorName: (data[nameField] ?? 'Acting captain').toString(),
          title: title,
          details: (data[detailsField] ?? '').toString(),
          isAuthorityEvent: false,
        ),
      );
    }

    for (final document in results[1].docs) {
      final data = document.data();
      addActingAction(
        data,
        uidField: 'staffId',
        nameField: 'staffName',
        timeField: 'timestamp',
        title: (data['action'] ?? 'Case action').toString(),
        detailsField: 'notes',
      );
    }
    for (final document in results[2].docs) {
      final data = document.data();
      addActingAction(
        data,
        uidField: 'requestedBy',
        nameField: 'requestedByName',
        timeField: 'requestedAt',
        title:
            'Cash movement: ${(data['type'] ?? '').toString().replaceAll('_', ' ')}',
      );
    }
    for (final document in results[3].docs) {
      final data = document.data();
      addActingAction(
        data,
        uidField: 'releasedBy',
        nameField: 'releasedByName',
        timeField: 'releasedAt',
        title: 'Incentive released',
      );
    }
    for (final document in results[4].docs) {
      final data = document.data();
      addActingAction(
        data,
        uidField: 'actorId',
        nameField: 'actorName',
        timeField: 'timestamp',
        title: (data['eventType'] ?? 'Audit action').toString().replaceAll(
          '_',
          ' ',
        ),
        detailsField: 'deletionReason',
      );
    }
    items.sort((a, b) => b.at.compareTo(a.at));
    return items;
  }

  DateTime _time(Map<String, dynamic> data, String field, {String? fallback}) {
    final value = data[field] ?? (fallback == null ? null : data[fallback]);
    return value is Timestamp
        ? value.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _AuthorityInterval {
  final DateTime start;
  DateTime end;

  _AuthorityInterval({required this.start, required this.end});
}

class _DelegationHistoryItem {
  final DateTime at;
  final String actorName;
  final String title;
  final String details;
  final bool isAuthorityEvent;

  const _DelegationHistoryItem({
    required this.at,
    required this.actorName,
    required this.title,
    required this.details,
    required this.isAuthorityEvent,
  });
}
