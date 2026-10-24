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
          const SizedBox(height: 8),
          if (status == statusNeedsCorrection) ...[
            _CorrectionNotice(data: data),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      _CaseCorrectionDialog(caseId: caseId, caseData: data),
                ),
                icon: const Icon(Icons.edit_document),
                label: const Text('Correct and resubmit this case'),
              ),
            ),
            const SizedBox(height: 8),
          ],
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

class _CorrectionNotice extends StatelessWidget {
  final Map<String, dynamic> data;

  const _CorrectionNotice({required this.data});

  @override
  Widget build(BuildContext context) {
    final request = Map<String, dynamic>.from(
      data['correctionRequest'] as Map? ?? const {},
    );
    final reason = (request['reason'] ?? '').toString();
    final fields = List<String>.from(request['fields'] ?? const []);
    final documents = List<String>.from(request['documents'] ?? const []);
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
            'Corrections requested',
            style: TextStyle(
              color: Colors.orange.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (reason.isNotEmpty) ...[const SizedBox(height: 4), Text(reason)],
          if (fields.isNotEmpty)
            Text('Information: ${fields.map(_friendlyFieldName).join(', ')}'),
          if (documents.isNotEmpty) Text('Documents: ${documents.join(', ')}'),
        ],
      ),
    );
  }
}

String _friendlyFieldName(String key) => key
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    )
    .replaceAll('_', ' ')
    .split(' ')
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

class _CaseCorrectionDialog extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> caseData;

  const _CaseCorrectionDialog({required this.caseId, required this.caseData});

  @override
  State<_CaseCorrectionDialog> createState() => _CaseCorrectionDialogState();
}

class _CaseCorrectionDialogState extends State<_CaseCorrectionDialog> {
  final _controllers = <String, TextEditingController>{};
  final _files = <String, PlatformFile>{};
  bool _saving = false;
  String? _error;

  Map<String, dynamic> get _correction => Map<String, dynamic>.from(
    widget.caseData['correctionRequest'] as Map? ?? const {},
  );

  List<String> get _fields =>
      List<String>.from(_correction['fields'] ?? const []);
  List<String> get _documents =>
      List<String>.from(_correction['documents'] ?? const []);

  @override
  void initState() {
    super.initState();
    final details = Map<String, dynamic>.from(
      widget.caseData['requestDetails'] as Map? ?? const {},
    );
    for (final field in _fields) {
      _controllers[field] = TextEditingController(
        text: (details[field] ?? '').toString(),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile(String name) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null || file.size > 2 * 1024 * 1024) {
      setState(
        () => _error = 'Files must be readable and no larger than 2 MB.',
      );
      return;
    }
    setState(() {
      _error = null;
      _files[name] = file;
    });
  }

  Future<void> _submit() async {
    if (_controllers.values.any(
      (controller) => controller.text.trim().isEmpty,
    )) {
      setState(() => _error = 'Complete every flagged information field.');
      return;
    }
    if (_documents.any((name) => !_files.containsKey(name))) {
      setState(
        () => _error = 'Upload a replacement for every flagged document.',
      );
      return;
    }
    final user = context.read<AuthService>().currentUserModel;
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final uploadedPaths = <String>[];
    try {
      final updatedDocuments = List<Map<String, dynamic>>.from(
        widget.caseData['documents'] ?? const [],
      );
      var index = 0;
      for (final name in _documents) {
        final file = _files[name]!;
        final extension = (file.extension ?? '').toLowerCase();
        final contentType = extension == 'pdf'
            ? 'application/pdf'
            : extension == 'png'
            ? 'image/png'
            : 'image/jpeg';
        final key = await AesGcm.with256bits().newSecretKey();
        final keyBytes = await key.extractBytes();
        final encrypted = await AesGcm.with256bits().encrypt(
          file.bytes!,
          secretKey: key,
        );
        final path =
            'caseDocuments/${user.uid}/correction_${const Uuid().v4()}/document_${++index}';
        await FirebaseDatabase.instance.ref(path).set({
          'ownerId': user.uid,
          'cipherText': base64Encode(encrypted.cipherText),
          'nonce': base64Encode(encrypted.nonce),
          'mac': base64Encode(encrypted.mac.bytes),
          'contentType': contentType,
          'size': file.size,
        });
        uploadedPaths.add(path);
        final replacement = {
          'name': name,
          'required': true,
          'status': 'uploaded',
          'fileName': file.name,
          'contentType': contentType,
          'size': file.size,
          'databasePath': path,
          'encryptionKey': base64Encode(keyBytes),
          // Firestore transforms such as serverTimestamp cannot be nested
          // inside a map that is itself stored in an array.
          'correctedAt': Timestamp.now(),
        };
        final existingIndex = updatedDocuments.indexWhere(
          (document) => document['name'] == name,
        );
        if (existingIndex < 0) {
          updatedDocuments.add(replacement);
        } else {
          updatedDocuments[existingIndex] = replacement;
        }
      }

      final details = Map<String, dynamic>.from(
        widget.caseData['requestDetails'] as Map? ?? const {},
      );
      for (final entry in _controllers.entries) {
        details[entry.key] = entry.value.text.trim();
      }
      final db = FirebaseFirestore.instance;
      final caseRef = db.collection('cases').doc(widget.caseId);
      final logRef = caseRef.collection('actionLog').doc();
      final returnStatus =
          (_correction['returnStatus'] ?? statusPendingReview).toString() ==
              statusProcessing
          ? statusProcessing
          : statusPendingReview;
      final batch = db.batch();
      batch.update(caseRef, {
        'requestDetails': details,
        'documents': updatedDocuments,
        'status': returnStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'correctionRequest.status': 'submitted',
        'correctionRequest.submittedAt': FieldValue.serverTimestamp(),
        'correctionRequest.submittedBy': user.uid,
      });
      batch.set(logRef, {
        'caseId': widget.caseId,
        'referenceNumber': widget.caseData['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': user.uid,
        'staffName': user.name,
        'action': 'Resident submitted requested corrections',
        'previousStatus': statusNeedsCorrection,
        'newStatus': returnStatus,
        'notes': 'Flagged information and documents were corrected.',
        'residentCorrection': true,
      });
      await batch.commit();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Corrections submitted for review in the same case.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      for (final path in uploadedPaths) {
        await FirebaseDatabase.instance.ref(path).remove();
      }
      if (mounted) {
        setState(() => _error = 'Could not submit corrections: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Correct case information'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((_correction['reason'] ?? '').toString()),
            const SizedBox(height: 16),
            ..._controllers.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: entry.value,
                  decoration: InputDecoration(
                    labelText: '${_friendlyFieldName(entry.key)} *',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            ..._documents.map(
              (name) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _files.containsKey(name)
                      ? Icons.check_circle
                      : Icons.upload_file,
                  color: _files.containsKey(name) ? Colors.green : null,
                ),
                title: Text(name),
                subtitle: Text(_files[name]?.name ?? 'Replacement required'),
                trailing: OutlinedButton(
                  onPressed: _saving ? null : () => _pickFile(name),
                  child: const Text('Choose file'),
                ),
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: Text(_saving ? 'Submitting…' : 'Resubmit case'),
      ),
    ],
  );
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
