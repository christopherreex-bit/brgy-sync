import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;
import '../../services/auth_service.dart';
import '../../services/case_status_service.dart';
import '../../services/twilio_service.dart';
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
        final isCaptain =
            context.watch<AuthService>().currentUserModel?.role == roleCaptain;
        final claimingApprovalPending =
            data['claimingApprovalStatus'] == 'pending';
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
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/dashboard');
                  }
                },
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
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
              if (claimingApprovalPending) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.admin_panel_settings_outlined,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pending Barangay Captain approval',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Requested by '
                                  '${data['claimingRequestedByName'] ?? 'Staff'} '
                                  'to move this case to For Claiming.',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                if ((data['claimingRequestReason'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Reason: ${data['claimingRequestReason']}',
                                    style: TextStyle(
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (isCaptain) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () =>
                                  _approveForClaiming(context, data),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Approve for Claiming'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _rejectForClaiming(context, data),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Reject for Claiming'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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
                              final databasePath = (d['databasePath'] ?? '')
                                  .toString();
                              final fileName = (d['fileName'] ?? '').toString();
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
                                        '${d['name'] ?? ''}'
                                        '${fileName.isEmpty ? '' : '\n$fileName'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: uploaded
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                    if (uploaded && databasePath.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () =>
                                            _openDocument(context, d),
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 16,
                                        ),
                                        label: const Text('Open'),
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
              if (!(claimingApprovalPending && isCaptain))
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

  Future<void> _approveForClaiming(
    BuildContext context,
    Map<String, dynamic> caseData,
  ) async {
    final user = context.read<AuthService>().currentUserModel;
    if (user?.role != roleCaptain) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the Barangay Captain can approve this request.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final referenceNumber = (caseData['referenceNumber'] ?? '').toString();
      final residentMobile = (caseData['residentMobile'] ?? '').toString();
      final smsTo = caseData['isSeedData'] == true || residentMobile.isEmpty
          ? TwilioService.fallbackNumber
          : residentMobile;
      final smsError = await TwilioService().sendStatusForClaiming(
        smsTo,
        referenceNumber,
      );
      await CaseStatusService().updateStatus(
        caseId: caseId,
        newStatus: statusForClaiming,
        notes: 'Barangay Captain approved the For Claiming request.',
        staffId: user!.uid,
        staffName: user.name,
        staffRole: user.role,
        referenceNumber: referenceNumber,
        smsSent: smsError == null,
        smsError: smsError,
        smsBody:
            'BrgySync: Your case $referenceNumber is ready for claiming. '
            'Please proceed to the barangay hall.',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              smsError == null
                  ? 'For Claiming approved and resident notified.'
                  : 'For Claiming approved. SMS was not sent: $smsError',
            ),
            backgroundColor: smsError == null ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not approve For Claiming: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectForClaiming(
    BuildContext context,
    Map<String, dynamic> caseData,
  ) async {
    final user = context.read<AuthService>().currentUserModel;
    if (user?.role != roleCaptain) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the Barangay Captain can reject this request.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    String? errorText;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.cancel_outlined,
            color: Colors.red.shade700,
            size: 34,
          ),
          title: const Text('Reject For Claiming request?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The case will return to Processing and its reserved '
                  'assistance amount will be returned to the available budget.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Reason for rejection *',
                    hintText: 'Explain why the request is being returned…',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final value = reasonController.text.trim();
                if (value.isEmpty) {
                  setDialogState(() {
                    errorText = 'A rejection reason is required.';
                  });
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              icon: const Icon(Icons.close_rounded),
              label: const Text('Reject Request'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (reason == null || !context.mounted) return;

    try {
      await CaseStatusService().rejectForClaimingApproval(
        caseId: caseId,
        reason: reason,
        captainId: user!.uid,
        captainName: user.name,
        captainRole: user.role,
        referenceNumber: (caseData['referenceNumber'] ?? '').toString(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'For Claiming request rejected. The case is back in Processing.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not reject For Claiming: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openDocument(
    BuildContext context,
    Map<String, dynamic> document,
  ) async {
    try {
      final path = (document['databasePath'] ?? '').toString();
      final encodedKey = (document['encryptionKey'] ?? '').toString();
      if (path.isEmpty || encodedKey.isEmpty) {
        throw StateError('This document has no downloadable file.');
      }

      final snapshot = await FirebaseDatabase.instance.ref(path).get();
      if (!snapshot.exists || snapshot.value is! Map) {
        throw StateError('The uploaded file could not be found.');
      }
      final raw = Map<Object?, Object?>.from(snapshot.value as Map);
      final encrypted = SecretBox(
        base64Decode(raw['cipherText'].toString()),
        nonce: base64Decode(raw['nonce'].toString()),
        mac: Mac(base64Decode(raw['mac'].toString())),
      );
      final clearBytes = await AesGcm.with256bits().decrypt(
        encrypted,
        secretKey: SecretKey(base64Decode(encodedKey)),
      );
      final contentType = (document['contentType'] ?? raw['contentType'] ?? '')
          .toString();
      final blob = html.Blob([clearBytes], contentType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
      Future<void>.delayed(
        const Duration(minutes: 1),
        () => html.Url.revokeObjectUrl(url),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
