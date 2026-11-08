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
            'Each temporary appointment is kept as a session. Open a session to review every recorded action performed during its authority window.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: FutureBuilder<List<_DelegationSession>>(
              future: _loadSessions(),
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
                final sessions = snapshot.data ?? const [];
                if (sessions.isEmpty) {
                  return const Center(
                    child: Text('No delegation sessions recorded yet.'),
                  );
                }
                return ListView.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _sessionCard(context, sessions[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionCard(BuildContext context, _DelegationSession session) {
    final status = session.status;
    final statusColor = switch (status) {
      'Active' => Colors.green,
      'Revoked' => Colors.red,
      _ => Colors.grey,
    };
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showSession(context, session),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Colors.orange.shade100,
                child: Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Colors.orange.shade900,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.delegateName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_roleLabel(session.delegateRole)} · ${_period(session)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    if (session.reason.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text('Reason: ${session.reason}'),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${session.performedActions.length} recorded ${session.performedActions.length == 1 ? 'action' : 'actions'} · Select to view session logs',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Chip(
                    label: Text(status),
                    side: BorderSide(color: statusColor.withValues(alpha: .35)),
                    backgroundColor: statusColor.withValues(alpha: .1),
                    labelStyle: TextStyle(
                      color: statusColor.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSession(
    BuildContext context,
    _DelegationSession session,
  ) async {
    final logs = [...session.logs]..sort((a, b) => b.at.compareTo(a.at));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${session.delegateName} · Delegation session'),
        content: SizedBox(
          width: 760,
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_roleLabel(session.delegateRole)}\n${_period(session)}'
                  '${session.reason.isEmpty ? '' : '\nReason: ${session.reason}'}',
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Session activity',
                style: TextStyle(fontWeight: FontWeight.bold, color: kNavy),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          'No activity was recorded in this session.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: log.isAuthorityEvent
                                  ? Colors.orange.shade100
                                  : Colors.blue.shade50,
                              child: Icon(
                                log.isAuthorityEvent
                                    ? Icons.admin_panel_settings_outlined
                                    : Icons.history,
                                color: log.isAuthorityEvent
                                    ? Colors.orange.shade900
                                    : kNavy,
                              ),
                            ),
                            title: Text(
                              log.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              [
                                DateFormat('MMM d, yyyy h:mm a').format(log.at),
                                if (log.details.isNotEmpty) log.details,
                              ].join(' · '),
                            ),
                            trailing: Chip(
                              label: Text(
                                log.isAuthorityEvent
                                    ? 'AUTHORITY'
                                    : 'ACTING ACTION',
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<List<_DelegationSession>> _loadSessions() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('captainDelegationEvents').get(),
      db.collectionGroup('actionLog').get(),
      db.collection('cashMovements').get(),
      db.collection('distributions').get(),
      db.collection('auditEvents').get(),
    ]);
    final eventDocs = [...results[0].docs]
      ..sort(
        (a, b) => _time(
          a.data(),
          'createdAt',
          fallback: 'startsAt',
        ).compareTo(_time(b.data(), 'createdAt', fallback: 'startsAt')),
      );
    final sessions = <_DelegationSession>[];

    for (final document in eventDocs) {
      final data = document.data();
      final type = (data['eventType'] ?? '').toString();
      final uid = (data['delegateUid'] ?? '').toString();
      final at = _time(data, 'createdAt', fallback: 'startsAt');
      if (type == 'granted' && uid.isNotEmpty) {
        final session = _DelegationSession(
          id: (data['sessionId'] ?? document.id).toString(),
          delegateUid: uid,
          delegateName: (data['delegateName'] ?? 'Acting captain').toString(),
          delegateRole: (data['delegateRole'] ?? '').toString(),
          start: _time(data, 'startsAt'),
          scheduledEnd: _time(data, 'expiresAt'),
          reason: (data['reason'] ?? '').toString(),
        );
        session.logs.add(
          _SessionLog(
            at: at,
            title: 'Temporary authority granted',
            details: session.reason,
            isAuthorityEvent: true,
          ),
        );
        sessions.add(session);
        continue;
      }
      final session = _findSessionForEvent(sessions, uid, data, at);
      if (session == null) continue;
      if (type == 'duration_changed') {
        session.scheduledEnd = _time(data, 'expiresAt');
        session.logs.add(
          _SessionLog(
            at: at,
            title: 'Delegation duration changed',
            details: (data['reason'] ?? '').toString(),
            isAuthorityEvent: true,
          ),
        );
      } else if (type == 'revoked') {
        session.revokedAt = at;
        final structuredReason = (data['revocationReasonLabel'] ?? '')
            .toString()
            .trim();
        final structuredDetails = (data['revocationReasonDetails'] ?? '')
            .toString()
            .trim();
        final reason = structuredReason.isEmpty
            ? (data['reason'] ?? '').toString()
            : structuredDetails.isEmpty
            ? structuredReason
            : '$structuredReason — $structuredDetails';
        session.logs.add(
          _SessionLog(
            at: at,
            title: 'Temporary authority revoked',
            details: reason,
            isAuthorityEvent: true,
          ),
        );
      }
    }

    void addAction(
      Map<String, dynamic> data, {
      required List<String> uidFields,
      required List<String> timeFields,
      required String title,
      List<String> detailFields = const ['notes', 'reason'],
    }) {
      final uid = _firstText(data, uidFields);
      final timestamp = _firstTime(data, timeFields);
      if (uid.isEmpty || timestamp == null) return;
      final session = _findSessionForAction(sessions, uid, timestamp);
      if (session == null) return;
      session.logs.add(
        _SessionLog(
          at: timestamp,
          title: title,
          details: _firstText(data, detailFields),
          isAuthorityEvent: false,
        ),
      );
    }

    for (final document in results[1].docs) {
      final data = document.data();
      final reference = _firstText(data, const ['referenceNumber', 'caseRef']);
      final action = _firstText(data, const ['action']);
      addAction(
        data,
        uidFields: const ['staffId', 'actorId'],
        timeFields: const ['timestamp', 'createdAt'],
        title:
            '${action.isEmpty ? 'Service request action' : action}${reference.isEmpty ? '' : ' · $reference'}',
      );
    }
    for (final document in results[2].docs) {
      final data = document.data();
      final reference = _firstText(data, const ['referenceNumber']);
      addAction(
        data,
        uidFields: const ['requestedBy', 'actorId'],
        timeFields: const ['requestedAt', 'timestamp', 'effectiveAt'],
        title:
            'Cash movement: ${(data['type'] ?? '').toString().replaceAll('_', ' ')}${reference.isEmpty ? '' : ' · $reference'}',
      );
    }
    for (final document in results[3].docs) {
      final data = document.data();
      final reference = _firstText(data, const ['referenceNumber']);
      addAction(
        data,
        uidFields: const ['releasedBy', 'requestedBy'],
        timeFields: const ['releasedAt', 'timestamp', 'createdAt'],
        title: 'Incentive released${reference.isEmpty ? '' : ' · $reference'}',
      );
    }
    for (final document in results[4].docs) {
      final data = document.data();
      final reference = _firstText(data, const ['referenceNumber']);
      final action = _firstText(data, const ['action', 'eventType']);
      addAction(
        data,
        uidFields: const ['actorId', 'staffId'],
        timeFields: const ['timestamp', 'createdAt'],
        title:
            '${action.isEmpty ? 'Audit action' : action.replaceAll('_', ' ')}${reference.isEmpty ? '' : ' · $reference'}',
        detailFields: const ['deletionReason', 'notes', 'reason'],
      );
    }

    sessions.sort((a, b) => b.start.compareTo(a.start));
    return sessions;
  }

  _DelegationSession? _findSessionForEvent(
    List<_DelegationSession> sessions,
    String uid,
    Map<String, dynamic> data,
    DateTime at,
  ) {
    final sessionId = (data['sessionId'] ?? '').toString();
    if (sessionId.isNotEmpty) {
      for (final session in sessions.reversed) {
        if (session.id == sessionId) return session;
      }
    }
    for (final session in sessions.reversed) {
      if (session.delegateUid == uid && !at.isBefore(session.start)) {
        return session;
      }
    }
    return null;
  }

  _DelegationSession? _findSessionForAction(
    List<_DelegationSession> sessions,
    String uid,
    DateTime at,
  ) {
    for (final session in sessions.reversed) {
      if (session.delegateUid != uid || at.isBefore(session.start)) continue;
      if (!at.isAfter(session.effectiveEnd)) return session;
    }
    return null;
  }

  DateTime _time(Map<String, dynamic> data, String field, {String? fallback}) {
    final value = data[field] ?? (fallback == null ? null : data[fallback]);
    return value is Timestamp
        ? value.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _firstTime(Map<String, dynamic> data, List<String> fields) {
    for (final field in fields) {
      final value = data[field];
      if (value is Timestamp) return value.toDate();
    }
    return null;
  }

  String _firstText(Map<String, dynamic> data, List<String> fields) {
    for (final field in fields) {
      final value = (data[field] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _period(_DelegationSession session) {
    final format = DateFormat('MMM d, yyyy h:mm a');
    return '${format.format(session.start)} – ${format.format(session.effectiveEnd)}';
  }

  String _roleLabel(String role) => switch (role.toLowerCase()) {
    'officer' => 'Barangay Officer',
    'staff' => 'Barangay Staff',
    _ => role.isEmpty ? 'Staff member' : role,
  };
}

class _DelegationSession {
  final String id;
  final String delegateUid;
  final String delegateName;
  final String delegateRole;
  final DateTime start;
  DateTime scheduledEnd;
  DateTime? revokedAt;
  final String reason;
  final List<_SessionLog> logs = [];

  _DelegationSession({
    required this.id,
    required this.delegateUid,
    required this.delegateName,
    required this.delegateRole,
    required this.start,
    required this.scheduledEnd,
    required this.reason,
  });

  DateTime get effectiveEnd => revokedAt ?? scheduledEnd;

  String get status {
    if (revokedAt != null) return 'Revoked';
    if (DateTime.now().isBefore(scheduledEnd)) return 'Active';
    return 'Completed';
  }

  List<_SessionLog> get performedActions =>
      logs.where((log) => !log.isAuthorityEvent).toList();
}

class _SessionLog {
  final DateTime at;
  final String title;
  final String details;
  final bool isAuthorityEvent;

  const _SessionLog({
    required this.at,
    required this.title,
    required this.details,
    required this.isAuthorityEvent,
  });
}
