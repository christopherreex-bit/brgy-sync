import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';

class CaseDetailScreen extends StatelessWidget {
  final String caseId;

  const CaseDetailScreen({super.key, required this.caseId});

  @override
  Widget build(BuildContext context) {
    // Single stream for case data — no nested StreamBuilders
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .snapshots(),
      builder: (context, caseSnapshot) {
        if (caseSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!caseSnapshot.hasData || !caseSnapshot.data!.exists) {
          return const Center(child: Text('Case not found.'));
        }

        final data = caseSnapshot.data!.data() as Map<String, dynamic>;
        final isConfidential = data['isConfidential'] ?? false;
        final residentName = isConfidential
            ? 'Confidential'
            : (data['residentName'] ?? '');
        final ref = data['referenceNumber'] ?? '';
        final status = data['status'] ?? '';
        final category = data['serviceCategory'] ?? '';
        final subType = data['serviceSubType'] ?? '';
        final channel = data['submissionChannel'] ?? 'portal';
        final ts = data['submissionTimestamp'];
        final dateStr = ts is Timestamp
            ? ts.toDate().toString().split('.').first
            : '';
        final documents = List<Map<String, dynamic>>.from(
          data['documents'] ?? [],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              TextButton.icon(
                onPressed: () => context.go('/dashboard'),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to case queue'),
              ),
              const SizedBox(height: 8),
              // Header
              Row(
                children: [
                  Text(
                    ref,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$dateStr · via ${channel == 'walkin' ? 'Walk-in' : 'Resident Portal'}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Two-column layout
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column
                  Expanded(
                    child: Column(
                      children: [
                        _infoCard('Resident Information', [
                          _row('Name', residentName),
                          _row('Address', data['residentAddress'] ?? ''),
                          _row('Contact', data['residentMobile'] ?? ''),
                        ]),
                        const SizedBox(height: 16),
                        _infoCard('Service Request Details', [
                          _row('Service Type', category.toUpperCase()),
                          _row('Sub-type', subType),
                          if (data['assistanceAmount'] != null)
                            _row(
                              'Assistance Amount',
                              '₱${data['assistanceAmount']}',
                            ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Right column
                  Expanded(
                    child: Column(
                      children: [
                        _infoCard('Submitted documents', [
                          if (documents.isEmpty)
                            const Text(
                              'No documents uploaded.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            )
                          else
                            ...documents.map((d) {
                              final uploaded = d['status'] == 'uploaded';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Icon(
                                      uploaded
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: uploaded
                                          ? Colors.green
                                          : Colors.red,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${d['name'] ?? ''} – ${uploaded ? 'uploaded' : 'missing'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: uploaded
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ]),
                        const SizedBox(height: 16),
                        _actionLogWidget(),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              // Action buttons
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      context.go('/dashboard/case/$caseId/update-status'),
                  icon: const Icon(Icons.edit),
                  label: const Text('Update status'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // Keep listening so a log written just after the case update appears
  // immediately without requiring the user to leave and reopen the case.
  Widget _actionLogWidget() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('actionLog')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Could not load action log: ${snapshot.error}',
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          );
        }
        final logs = [...?snapshot.data?.docs];
        logs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTimestamp = aData['timestamp'] as Timestamp?;
          final bTimestamp = bData['timestamp'] as Timestamp?;
          return (bTimestamp?.millisecondsSinceEpoch ?? 0).compareTo(
            aTimestamp?.millisecondsSinceEpoch ?? 0,
          );
        });
        final visibleLogs = logs.take(50);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Action log',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: kNavy,
                ),
              ),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                const Text(
                  'No actions recorded yet.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                )
              else
                ...visibleLogs.map((doc) {
                  final log = doc.data() as Map<String, dynamic>;
                  final ts = log['timestamp'] is Timestamp
                      ? (log['timestamp'] as Timestamp).toDate()
                      : DateTime.now();
                  final tsStr =
                      '${ts.month}/${ts.day}/${ts.year} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
                  final smsSent = log['smsSent'] ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: const BoxDecoration(
                            color: kNavy,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                                        borderRadius: BorderRadius.circular(10),
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
                                '${log['staffName'] ?? ''} · $tsStr',
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
                }),
            ],
          ),
        );
      },
    );
  }
}
