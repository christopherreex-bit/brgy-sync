import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../utils/constants.dart';

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  final _searchCtrl = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Audit Trail',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chronological log of case activity and staff actions.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          // Search
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText:
                        'Search by reference number, staff name, or action',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              // Date from
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _dateFrom ?? DateTime.now(),
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _dateFrom = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _dateFrom != null
                        ? '${_dateFrom!.month}/${_dateFrom!.day}/${_dateFrom!.year}'
                        : 'Date From',
                    style: TextStyle(
                      fontSize: 13,
                      color: _dateFrom != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Date to
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _dateTo ?? DateTime.now(),
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _dateTo = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _dateTo != null
                        ? '${_dateTo!.month}/${_dateTo!.day}/${_dateTo!.year}'
                        : 'Date To',
                    style: TextStyle(
                      fontSize: 13,
                      color: _dateTo != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Results — aggregate from all cases
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchAuditLogs(),
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
                final logs = snapshot.data ?? [];
                if (logs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No audit logs yet.',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Actions will appear here as staff update cases.',
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
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final ts = log['timestamp'] is Timestamp
                        ? (log['timestamp'] as Timestamp).toDate()
                        : DateTime.now();
                    final tsStr =
                        '${ts.month}/${ts.day}/${ts.year} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
                    final smsSent = log['smsSent'] ?? false;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _showAuditDetails(log),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: kNavy,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              log['action'] ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          if (smsSent)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'SMS sent',
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${log['caseRef'] ?? ''} · ${log['staffName'] ?? ''} · $tsStr',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (log['notes'] != null &&
                                          log['notes'].toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            log['notes'],
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
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

  Future<void> _showAuditDetails(Map<String, dynamic> log) async {
    final timestamp = log['timestamp'] is Timestamp
        ? (log['timestamp'] as Timestamp).toDate()
        : null;
    final details = <MapEntry<String, String>>[
      MapEntry('Action', _text(log['action'])),
      MapEntry('Case reference', _text(log['caseRef'])),
      MapEntry('Performed by', _text(log['staffName'])),
      if (_text(log['actorRole']).isNotEmpty)
        MapEntry('Role', _titleCase(_text(log['actorRole']))),
      if (timestamp != null)
        MapEntry(
          'Date and time',
          DateFormat('MMMM d, yyyy · h:mm:ss a').format(timestamp),
        ),
      if (_text(log['previousStatus']).isNotEmpty)
        MapEntry(
          'Previous status',
          caseStatusLabel(_text(log['previousStatus'])),
        ),
      if (_text(log['newStatus']).isNotEmpty)
        MapEntry('New status', caseStatusLabel(_text(log['newStatus']))),
      if (_text(log['residentName']).isNotEmpty)
        MapEntry('Resident', _text(log['residentName'])),
      if (_text(log['serviceCategory']).isNotEmpty)
        MapEntry('Category', _text(log['serviceCategory'])),
      if (_text(log['serviceSubType']).isNotEmpty)
        MapEntry('Service', _text(log['serviceSubType'])),
      if (_text(log['notes']).isNotEmpty)
        MapEntry('Notes / reason', _text(log['notes'])),
      if (_text(log['deletionReason']).isNotEmpty &&
          _text(log['deletionReason']) != _text(log['notes']))
        MapEntry('Deletion reason', _text(log['deletionReason'])),
      if ((log['budgetReversalAmount'] as num?) != null)
        MapEntry(
          'Budget restored',
          '₱${(log['budgetReversalAmount'] as num).toStringAsFixed(2)}',
        ),
      MapEntry(
        'SMS notification',
        log['smsSent'] == true ? 'Sent' : 'Not sent',
      ),
      if (_text(log['smsBody']).isNotEmpty)
        MapEntry('SMS message', _text(log['smsBody'])),
      if (_text(log['smsError']).isNotEmpty)
        MapEntry('SMS error', _text(log['smsError'])),
    ].where((entry) => entry.value.isNotEmpty).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: kNavy),
            SizedBox(width: 10),
            Expanded(child: Text('Audit record details')),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility_outlined, size: 18, color: kNavy),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Read-only record — no changes can be made here.',
                          style: TextStyle(color: kNavy, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in details)
                  _AuditDetailRow(label: entry.key, value: entry.value),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: FilledButton.styleFrom(backgroundColor: kNavy),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _titleCase(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Future<List<Map<String, dynamic>>> _fetchAuditLogs() async {
    final db = FirebaseFirestore.instance;
    final snapshots = await Future.wait([
      db
          .collectionGroup('actionLog')
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get(),
      db
          .collection('auditEvents')
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get(),
    ]);

    final List<Map<String, dynamic>> allLogs = [];
    for (final logDoc in [...snapshots[0].docs, ...snapshots[1].docs]) {
      final log = Map<String, dynamic>.from(logDoc.data());

      log['staffName'] ??= log['actorName'] ?? '';
      if (_text(log['action']).isEmpty) {
        log['action'] = _titleCase(_text(log['eventType']));
      }

      // Use stored case reference instead of fetching parent document
      final caseRefNum =
          (log['referenceNumber'] as String?) ??
          (log['caseId'] as String?) ??
          '';
      log['caseRef'] = caseRefNum;

      // Date filter
      if (_dateFrom != null || _dateTo != null) {
        final ts = log['timestamp'] is Timestamp
            ? (log['timestamp'] as Timestamp).toDate()
            : null;
        if (ts != null) {
          if (_dateFrom != null && ts.isBefore(_dateFrom!)) continue;
          if (_dateTo != null &&
              ts.isAfter(_dateTo!.add(const Duration(days: 1)))) {
            continue;
          }
        }
      }

      // Search filter
      final queryStr = _searchCtrl.text.trim().toLowerCase();
      if (queryStr.isNotEmpty) {
        final action = (log['action'] ?? '').toString().toLowerCase();
        final staff = (log['staffName'] ?? '').toString().toLowerCase();
        final ref = caseRefNum.toString().toLowerCase();
        if (!action.contains(queryStr) &&
            !staff.contains(queryStr) &&
            !ref.contains(queryStr)) {
          continue;
        }
      }

      allLogs.add(log);
    }

    allLogs.sort((a, b) {
      final aTime = a['timestamp'] as Timestamp?;
      final bTime = b['timestamp'] as Timestamp?;
      return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
        aTime?.millisecondsSinceEpoch ?? 0,
      );
    });
    return allLogs;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}

class _AuditDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _AuditDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
