import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      log['notes'],
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
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
