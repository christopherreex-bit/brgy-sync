import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';
import '../../services/auth_service.dart';
import '../../services/case_workflow_service.dart';
import '../../services/export_service.dart';
import '../../services/firestore_service.dart';

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
                  (doc) => _CaseCard(
                    caseId: doc.id,
                    data: doc.data() as Map<String, dynamic>,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CaseCard extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;

  const _CaseCard({required this.caseId, required this.data});

  @override
  Widget build(BuildContext context) {
    final ref = data['referenceNumber'] ?? '';
    final category = data['serviceCategory'] ?? '';
    final subType = data['serviceSubType'] ?? '';
    final status = data['status'] ?? statusPendingReview;
    final normalizedStatus = normalizeCaseStatus(status.toString());
    final assistanceAmount = (data['assistanceAmount'] as num?)?.toDouble();
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _confirmDelete(context, ref.toString()),
                tooltip: 'Delete case',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
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
              if (assistanceAmount != null && assistanceAmount > 0)
                _DetailChip(
                  icon: Icons.payments_outlined,
                  label: 'Assistance ₱${_formatAmount(assistanceAmount)}',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    ExportService.generateCaseAcknowledgmentPdf(caseData: data),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Acknowledgment PDF'),
              ),
              if ([
                statusPendingReview,
                statusProcessing,
              ].contains(normalizedStatus))
                OutlinedButton.icon(
                  onPressed: () => _cancelCase(context),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel request'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
            ],
          ),
          if (data['residentActionRequired'] == true) ...[
            const SizedBox(height: 12),
            _CorrectionPanel(caseId: caseId, data: data),
          ],
          if (normalizedStatus == statusForClaiming) ...[
            const SizedBox(height: 12),
            _ClaimingDetails(data: data),
          ],
          if (normalizedStatus == statusReleased) ...[
            const SizedBox(height: 12),
            _FeedbackPanel(caseId: caseId, data: data),
          ],
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              leading: const Icon(Icons.history, color: kNavy, size: 20),
              title: const Text(
                'Status history',
                style: TextStyle(
                  color: kNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                _StatusHistory(
                  caseId: caseId,
                  initialStatus: status.toString(),
                  submittedAt: submitted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$grouped.${parts.last}';
  }

  Future<void> _cancelCase(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel this request?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Cancellation reason *',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep request'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => errorText = 'A reason is required.');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Cancel request'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;
    try {
      final user = context.read<AuthService>().currentUserModel!;
      await CaseWorkflowService().cancelCase(
        caseId: caseId,
        residentId: user.uid,
        residentName: user.name,
        reason: reason,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not cancel case: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String reference) async {
    final reasonController = TextEditingController();
    String? reasonError;
    final deletionReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete case?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permanently delete $reference and its action log? '
                'Any recorded budget deduction will be reversed.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason for deletion *',
                  border: const OutlineInputBorder(),
                  errorText: reasonError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  setDialogState(
                    () => reasonError = 'Please enter a reason for deletion.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, reason);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (deletionReason == null || !context.mounted) return;

    try {
      final user = context.read<AuthService>().currentUserModel;
      if (user == null) throw StateError('Please sign in again.');
      await FirestoreService().deleteCase(
        caseId,
        actorId: user.uid,
        actorName: user.name,
        actorRole: user.role,
        source: 'resident_my_cases',
        deletionReason: deletionReason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$reference was deleted.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete case: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _CorrectionPanel extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;

  const _CorrectionPanel({required this.caseId, required this.data});

  @override
  State<_CorrectionPanel> createState() => _CorrectionPanelState();
}

class _CorrectionPanelState extends State<_CorrectionPanel> {
  int? _uploadingIndex;

  @override
  Widget build(BuildContext context) {
    final documents = List<Map<String, dynamic>>.from(
      widget.data['documents'] ?? [],
    );
    final invalidEntries = documents.asMap().entries.where(
      (entry) => entry.value['verificationStatus'] == 'invalid',
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resident action required',
            style: TextStyle(
              color: Colors.orange.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...invalidEntries.map((entry) {
            final document = entry.value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text((document['name'] ?? 'Document').toString()),
              subtitle: Text(
                'Reason: ${document['verificationReason'] ?? 'Replacement required'}',
              ),
              trailing: FilledButton.icon(
                onPressed: _uploadingIndex == null
                    ? () => _replace(entry.key, document)
                    : null,
                icon: _uploadingIndex == entry.key
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('Replace'),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _replace(int index, Map<String, dynamic> oldDocument) async {
    try {
      final user = context.read<AuthService>().currentUserModel!;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return;
      final file = result.files.single;
      if (file.size > 2 * 1024 * 1024) {
        throw StateError('Files must not exceed 2 MB.');
      }
      final extension = (file.extension ?? '').toLowerCase();
      final contentType = switch (extension) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => throw StateError('Only PDF, JPG, JPEG, and PNG are allowed.'),
      };
      setState(() => _uploadingIndex = index);
      final path =
          'caseDocuments/${user.uid}/${const Uuid().v4()}/replacement_${index + 1}';
      final algorithm = AesGcm.with256bits();
      final secretKey = await algorithm.newSecretKey();
      final keyBytes = await secretKey.extractBytes();
      final encrypted = await algorithm.encrypt(
        file.bytes!,
        secretKey: secretKey,
      );
      await FirebaseDatabase.instance.ref(path).set({
        'ownerId': user.uid,
        'cipherText': base64Encode(encrypted.cipherText),
        'nonce': base64Encode(encrypted.nonce),
        'mac': base64Encode(encrypted.mac.bytes),
        'contentType': contentType,
        'size': file.size,
      });
      await CaseWorkflowService().replaceDocument(
        caseId: widget.caseId,
        documentIndex: index,
        residentId: user.uid,
        residentName: user.name,
        replacement: {
          'status': 'uploaded',
          'fileName': file.name,
          'contentType': contentType,
          'size': file.size,
          'databasePath': path,
          'encryptionKey': base64Encode(keyBytes),
        },
      );
      final oldPath = (oldDocument['databasePath'] ?? '').toString();
      if (oldPath.isNotEmpty) {
        await FirebaseDatabase.instance.ref(oldPath).remove();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not replace document: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingIndex = null);
    }
  }
}

class _ClaimingDetails extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ClaimingDetails({required this.data});

  @override
  Widget build(BuildContext context) {
    final approvedAt = data['claimingApprovedAt'] as Timestamp?;
    final deadline = approvedAt?.toDate().add(const Duration(days: 30));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        border: Border.all(color: Colors.purple.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready for claiming',
            style: TextStyle(
              color: Colors.purple.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text('Location: Barangay Calzada-Tipas Hall'),
          const Text('Hours: Monday–Friday, 8:00 AM–5:00 PM'),
          const Text('Bring: Valid government-issued ID and this case number'),
          if (deadline != null)
            Text(
              'Claim on or before: '
              '${deadline.month}/${deadline.day}/${deadline.year}',
            ),
          if ((data['assistanceAmount'] as num?) != null)
            Text(
              'Approved assistance: '
              '₱${(data['assistanceAmount'] as num).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}

class _FeedbackPanel extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;

  const _FeedbackPanel({required this.caseId, required this.data});

  @override
  State<_FeedbackPanel> createState() => _FeedbackPanelState();
}

class _FeedbackPanelState extends State<_FeedbackPanel> {
  int _rating = 0;
  bool _improperRequest = false;
  bool _saving = false;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.data['residentFeedback'];
    if (existing is Map) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Thank you for your feedback. Rating: ${existing['rating']}/5',
          style: TextStyle(color: Colors.green.shade800),
        ),
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Rate this service'),
      children: [
        Row(
          children: List.generate(
            5,
            (index) => IconButton(
              onPressed: () => setState(() => _rating = index + 1),
              icon: Icon(
                index < _rating ? Icons.star : Icons.star_border,
                color: Colors.amber.shade700,
              ),
            ),
          ),
        ),
        TextField(
          controller: _commentController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Optional comment',
            border: OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _improperRequest,
          onChanged: (value) =>
              setState(() => _improperRequest = value ?? false),
          title: const Text(
            'A staff member requested money, a favor, or something improper',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _saving || _rating == 0 ? null : _submit,
            child: const Text('Submit feedback'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final user = context.read<AuthService>().currentUserModel!;
      await CaseWorkflowService().submitFeedback(
        caseId: widget.caseId,
        residentId: user.uid,
        rating: _rating,
        comment: _commentController.text,
        improperRequestReported: _improperRequest,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not submit feedback: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StatusHistory extends StatelessWidget {
  final String caseId;
  final String initialStatus;
  final DateTime? submittedAt;

  const _StatusHistory({
    required this.caseId,
    required this.initialStatus,
    required this.submittedAt,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('actionLog')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Could not load status history.',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          );
        }

        final logs = [...?snapshot.data?.docs]
            .map((doc) => doc.data() as Map<String, dynamic>)
            .where((log) => (log['newStatus'] ?? '').toString().isNotEmpty)
            .toList();
        logs.sort((a, b) {
          final aTimestamp = a['timestamp'] as Timestamp?;
          final bTimestamp = b['timestamp'] as Timestamp?;
          return (aTimestamp?.millisecondsSinceEpoch ?? 0).compareTo(
            bTimestamp?.millisecondsSinceEpoch ?? 0,
          );
        });

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _StatusHistoryEntry(
                status: logs.isEmpty
                    ? initialStatus
                    : (logs.first['previousStatus'] ?? statusPendingReview)
                          .toString(),
                timestamp: submittedAt,
                note: 'Request submitted',
                isLast: logs.isEmpty,
              ),
              ...logs.asMap().entries.map((entry) {
                final log = entry.value;
                final timestamp = log['timestamp'] is Timestamp
                    ? (log['timestamp'] as Timestamp).toDate()
                    : null;
                return _StatusHistoryEntry(
                  status: log['newStatus'].toString(),
                  timestamp: timestamp,
                  note: (log['notes'] ?? '').toString().trim(),
                  isLast: entry.key == logs.length - 1,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _StatusHistoryEntry extends StatelessWidget {
  final String status;
  final DateTime? timestamp;
  final String note;
  final bool isLast;

  const _StatusHistoryEntry({
    required this.status,
    required this.timestamp,
    required this.note,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = timestamp == null
        ? 'Timestamp pending'
        : '${timestamp!.month}/${timestamp!.day}/${timestamp!.year} '
              '${timestamp!.hour.toString().padLeft(2, '0')}:'
              '${timestamp!.minute.toString().padLeft(2, '0')}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: kNavy,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Colors.grey.shade300),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(status: status),
                  const SizedBox(height: 4),
                  Text(
                    dateText,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        note,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
