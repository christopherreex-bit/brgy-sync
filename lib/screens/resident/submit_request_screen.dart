import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/service_category.dart';
import '../../models/case_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/twilio_service.dart';
import '../../utils/constants.dart';
import '../../utils/sla_calculator.dart' as sla;

class SubmitRequestScreen extends StatefulWidget {
  final String? initialCategoryId;
  final String? initialSubType;

  const SubmitRequestScreen({
    super.key,
    this.initialCategoryId,
    this.initialSubType,
  });

  @override
  State<SubmitRequestScreen> createState() => _SubmitRequestScreenState();
}

class _SubmitRequestScreenState extends State<SubmitRequestScreen> {
  String? _selectedCategoryId;
  String? _selectedSubType;
  List<FormFieldConfig> _fields = [];
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _dropdownValues = {};
  final Map<String, String?> _radioValues = {};
  final Map<String, DateTime?> _dateValues = {};
  bool _loading = false;
  bool _submitted = false;
  String? _refNumber;
  bool _requestingForSomeoneElse = false;

  final _firestore = FirestoreService();
  final _twilio = TwilioService();
  final _database = FirebaseDatabase.instance;
  final _encryption = AesGcm.with256bits();
  final _uuid = const Uuid();
  final List<String> _uploadedDatabasePaths = [];

  // BASS documents
  List<BassDocument>? _bassDocs;

  // Field validation errors
  final Map<String, String?> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialCategoryId != null) {
      _selectedCategoryId = widget.initialCategoryId;
      if (widget.initialSubType != null) {
        _selectedSubType = widget.initialSubType;
      }
      if (_selectedSubType != null) {
        _loadForm();
      }
    }
  }

  void _loadForm() {
    if (_selectedCategoryId == null || _selectedSubType == null) return;
    if (!{'bass', 'beneficiary'}.contains(_selectedCategoryId)) {
      _requestingForSomeoneElse = false;
    }
    _fields = formFieldsFor(_selectedCategoryId!, _selectedSubType!);
    _controllers.clear();
    _dropdownValues.clear();
    _radioValues.clear();
    _dateValues.clear();
    _fieldErrors.clear();
    for (final f in _fields) {
      _controllers[f.key] = TextEditingController();
      if (f.type == FormFieldType.dropdown) _dropdownValues[f.key] = null;
      if (f.type == FormFieldType.radio) _radioValues[f.key] = null;
      if (f.type == FormFieldType.date) _dateValues[f.key] = null;
    }
    if (!_requestingForSomeoneElse) {
      _prefillLoggedInResident();
    }
    // BASS doc checklist
    if (_selectedCategoryId == 'bass') {
      _bassDocs = kBassDocuments(_selectedSubType!);
    } else {
      _bassDocs = null;
    }
  }

  static const _personNameKeys = {
    'fullName',
    'patientName',
    'beneficiaryName',
    'studentName',
    'reporterName',
  };

  bool _isFieldVisible(FormFieldConfig field) {
    if (_requestingForSomeoneElse) return true;
    if (_selectedCategoryId == 'bass' && field.key == 'relationship') {
      return false;
    }
    if (_selectedCategoryId == 'beneficiary' &&
        field.key == 'requesterRelationship') {
      return false;
    }
    return true;
  }

  void _prefillLoggedInResident() {
    final user = context.read<AuthService>().currentUserModel;
    if (user == null) return;

    final nameParts = user.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (_controllers['firstName'] != null && nameParts.isNotEmpty) {
      _controllers['firstName']!.text = nameParts.first;
      if (_controllers['surname'] != null && nameParts.length > 1) {
        _controllers['surname']!.text = nameParts.last;
      }
    }

    for (final key in _personNameKeys) {
      final controller = _controllers[key];
      if (controller != null) {
        controller.text = user.name;
        break;
      }
    }
    final contactController = _controllers['contact'];
    if (contactController != null) {
      contactController.text = user.mobile;
    }
  }

  void _setRequestingForSomeoneElse(bool value) {
    setState(() {
      _requestingForSomeoneElse = value;
      _fieldErrors.clear();
      for (final document in _bassDocs ?? <BassDocument>[]) {
        if (document.requiredWhenRequestingForSomeoneElse) {
          document.required = value;
          if (!value) {
            document.uploaded = false;
            document.fileName = null;
            document.contentType = null;
            document.size = null;
            document.bytes = null;
          }
        }
      }

      for (final key in _personNameKeys) {
        _controllers[key]?.clear();
      }
      _controllers['firstName']?.clear();
      _controllers['surname']?.clear();
      _controllers['middleInitial']?.clear();
      _controllers['contact']?.clear();
      if (!value && _selectedCategoryId == 'bass') {
        _controllers['relationship']?.clear();
      }
      if (!value && _selectedCategoryId == 'beneficiary') {
        _controllers['requesterRelationship']?.clear();
      }

      if (!value) {
        _prefillLoggedInResident();
      }
    });
  }

  String _applicantName(Map<String, dynamic> formData, String fallbackName) {
    for (final key in _personNameKeys) {
      final value = formData[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    final firstName = formData['firstName']?.toString().trim() ?? '';
    final middleInitial = formData['middleInitial']?.toString().trim() ?? '';
    final surname = formData['surname']?.toString().trim() ?? '';
    final composedName = [
      firstName,
      middleInitial,
      surname,
    ].where((part) => part.isNotEmpty).join(' ');
    return composedName.isNotEmpty ? composedName : fallbackName;
  }

  /// Validate a single field and update error state
  String? _validateField(FormFieldConfig f) {
    String? textValue;
    DateTime? dateValue;
    String? dropdownValue;
    String? radioValue;

    switch (f.type) {
      case FormFieldType.text:
      case FormFieldType.email:
      case FormFieldType.number:
      case FormFieldType.phone:
      case FormFieldType.textarea:
        textValue = _controllers[f.key]?.text;
        break;
      case FormFieldType.dropdown:
        dropdownValue = _dropdownValues[f.key];
        break;
      case FormFieldType.radio:
        radioValue = _radioValues[f.key];
        break;
      case FormFieldType.date:
        dateValue = _dateValues[f.key];
        break;
    }

    final error = validateField(
      f,
      textValue,
      dateValue,
      dropdownValue,
      radioValue,
    );
    setState(() {
      _fieldErrors[f.key] = error;
    });
    return error;
  }

  /// Validate all fields
  bool _validateAllFields() {
    bool isValid = true;
    for (final f in _fields) {
      if (_isFieldVisible(f) && f.required) {
        final error = _validateField(f);
        if (error != null) isValid = false;
      }
    }
    // Validate BASS documents
    if (_bassDocs != null) {
      final missingRequired = _bassDocs!
          .where((d) => d.required && !d.uploaded)
          .toList();
      if (missingRequired.isNotEmpty) {
        _showError(
          'Please upload all required documents: ${missingRequired.map((d) => d.name).join(', ')}',
        );
        return false;
      }
    }
    return isValid;
  }

  /// Called externally (from HomeScreen) to set the category.
  void setCategory(String categoryId, {String? subType}) {
    setState(() {
      _selectedCategoryId = categoryId;
      final cat = kServiceCategories.firstWhere((c) => c.id == categoryId);
      _selectedSubType =
          subType ?? (cat.subTypes.isNotEmpty ? cat.subTypes.first : null);
      _submitted = false;
      _refNumber = null;
      _loadForm();
    });
  }

  Future<void> _submit() async {
    // Issue #3 fix: rate limiting — max 5 cases per resident per hour
    final auth = context.read<AuthService>();
    final user = auth.currentUserModel;
    if (user == null) {
      _showError('Not logged in.');
      return;
    }
    try {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final recentCases = await FirebaseFirestore.instance
          .collection('cases')
          .where('residentId', isEqualTo: user.uid)
          .where(
            'submissionTimestamp',
            isGreaterThan: Timestamp.fromDate(oneHourAgo),
          )
          .count()
          .get();
      if ((recentCases.count ?? 0) >= 5) {
        _showError(
          'Rate limit exceeded. You can submit up to 5 cases per hour.',
        );
        return;
      }
    } catch (e) {
      // If rate limit check fails, allow submission (fail-open)
      debugPrint('Rate limit check failed: $e');
    }

    // Validate all fields using new validation
    if (!_validateAllFields()) {
      return;
    }

    setState(() => _loading = true);

    try {
      // Build form data
      final formData = <String, dynamic>{};
      for (final f in _fields) {
        if (!_isFieldVisible(f)) continue;
        switch (f.type) {
          case FormFieldType.text:
          case FormFieldType.email:
          case FormFieldType.number:
          case FormFieldType.phone:
          case FormFieldType.textarea:
            formData[f.key] = _controllers[f.key]?.text.trim() ?? '';
            break;
          case FormFieldType.dropdown:
            formData[f.key] = _dropdownValues[f.key];
            break;
          case FormFieldType.radio:
            formData[f.key] = _radioValues[f.key];
            break;
          case FormFieldType.date:
            formData[f.key] = _dateValues[f.key]?.toIso8601String();
            break;
        }
      }

      final documents = await _uploadDocuments(user.uid);

      // Compute SLA
      final now = DateTime.now();
      final slaSnapshot = await FirebaseFirestore.instance
          .collection('slaConfig')
          .get();
      final slaConfig = sla.buildSlaConfig(
        slaSnapshot.docs.map((doc) => doc.data()),
      );
      final deadline = sla.computeDeadline(
        now,
        _selectedCategoryId!,
        _selectedSubType!,
        config: slaConfig,
      );

      final caseData = CaseModel(
        residentId: user.uid,
        residentName: _applicantName(formData, user.name),
        residentMobile: user.mobile,
        residentAddress: formData['address'] ?? '',
        requestedForSelf: !_requestingForSomeoneElse,
        requesterName: user.name,
        requesterMobile: user.mobile,
        serviceCategory: _selectedCategoryId!,
        serviceSubType: _selectedSubType!,
        status: statusPendingReview,
        submissionChannel: 'portal',
        submissionTimestamp: now,
        slaDeadline: deadline,
        slaStatus: 'on_time',
        isConfidential: kServiceCategories
            .firstWhere((c) => c.id == _selectedCategoryId!)
            .isConfidential,
        documents: documents,
        assistanceAmount:
            formData['assistanceAmount'] != null &&
                formData['assistanceAmount'].toString().isNotEmpty
            ? double.tryParse(formData['assistanceAmount'].toString())
            : null,
      );

      final refNumber = await _firestore.createCase(caseData);
      _uploadedDatabasePaths.clear();
      final smsTo = user.isSeedData == true
          ? TwilioService.fallbackNumber
          : user.mobile;
      final smsResult = await _twilio.sendSubmissionAck(smsTo, refNumber);

      if (mounted) {
        setState(() {
          _loading = false;
          _submitted = true;
          _refNumber = refNumber;
        });
        if (smsResult != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Case submitted. SMS notification could not be sent: $smsResult',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      await _deletePendingUploads();
      if (mounted) {
        setState(() => _loading = false);
        _showError('Submission failed: $e');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _reset() {
    setState(() {
      _submitted = false;
      _refNumber = null;
      _selectedCategoryId = null;
      _selectedSubType = null;
      _fields = [];
      _controllers.clear();
      _dropdownValues.clear();
      _radioValues.clear();
      _dateValues.clear();
      _bassDocs = null;
      _requestingForSomeoneElse = false;
      _uploadedDatabasePaths.clear();
    });
  }

  Future<void> _pickDocument(BassDocument document) async {
    if (document.requiredWhenRequestingForSomeoneElse &&
        !_requestingForSomeoneElse) {
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.bytes == null) {
        _showError('Could not read the selected file.');
        return;
      }
      if (file.size > 2 * 1024 * 1024) {
        _showError('Files must not exceed 2 MB.');
        return;
      }

      final extension = (file.extension ?? '').toLowerCase();
      final contentType = switch (extension) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => null,
      };
      if (contentType == null) {
        _showError('Only PDF, JPG, JPEG, and PNG files are allowed.');
        return;
      }

      setState(() {
        document.uploaded = true;
        document.fileName = file.name;
        document.contentType = contentType;
        document.size = file.size;
        document.bytes = file.bytes;
      });
    } catch (e) {
      _showError('Could not select document: $e');
    }
  }

  void _removeDocument(BassDocument document) {
    setState(() {
      document.uploaded = false;
      document.fileName = null;
      document.contentType = null;
      document.size = null;
      document.bytes = null;
    });
  }

  Future<List<Map<String, dynamic>>> _uploadDocuments(String residentId) async {
    if (_bassDocs == null) return [];

    final requestId = _uuid.v4();
    final documents = <Map<String, dynamic>>[];
    for (var index = 0; index < _bassDocs!.length; index++) {
      final document = _bassDocs![index];
      if (!document.uploaded || document.bytes == null) {
        documents.add({
          'name': document.name,
          'required': document.required,
          'status':
              document.requiredWhenRequestingForSomeoneElse &&
                  !_requestingForSomeoneElse
              ? 'not_applicable'
              : 'missing',
        });
        continue;
      }

      final databasePath =
          'caseDocuments/$residentId/$requestId/document_${index + 1}';
      final secretKey = await _encryption.newSecretKey();
      final secretKeyBytes = await secretKey.extractBytes();
      final encrypted = await _encryption.encrypt(
        document.bytes!,
        secretKey: secretKey,
      );
      await _database.ref(databasePath).set({
        'ownerId': residentId,
        'cipherText': base64Encode(encrypted.cipherText),
        'nonce': base64Encode(encrypted.nonce),
        'mac': base64Encode(encrypted.mac.bytes),
        'contentType': document.contentType,
        'size': document.size,
      });
      _uploadedDatabasePaths.add(databasePath);
      documents.add({
        'name': document.name,
        'required': document.required,
        'status': 'uploaded',
        'fileName': document.fileName,
        'contentType': document.contentType,
        'size': document.size,
        'databasePath': databasePath,
        'encryptionKey': base64Encode(secretKeyBytes),
      });
    }
    return documents;
  }

  Future<void> _deletePendingUploads() async {
    final paths = List<String>.from(_uploadedDatabasePaths);
    _uploadedDatabasePaths.clear();
    for (final path in paths) {
      try {
        await _database.ref(path).remove();
      } catch (_) {
        // Best-effort cleanup after an unsuccessful case submission.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted && _refNumber != null) {
      return _buildConfirmation();
    }
    if (_selectedCategoryId == null) {
      return _buildCategoryPicker();
    }
    if (_selectedSubType == null) {
      return _buildSubTypePicker();
    }
    return _buildForm();
  }

  // ─── Step 1: Pick Category ───────────────────────────────────────
  Widget _buildCategoryPicker() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Submit a Request',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select a service category to begin.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              final cat = kServiceCategories[index];
              return _catCard(cat);
            },
          ),
          const SizedBox(height: 12),
          _catCard(kServiceCategories[6], isWide: true),
        ],
      ),
    );
  }

  Widget _catCard(ServiceCategory cat, {bool isWide = false}) {
    return InkWell(
      onTap: () {
        if (cat.subTypes.length == 1) {
          // Only one sub-type, go directly to form
          setState(() {
            _selectedCategoryId = cat.id;
            _selectedSubType = cat.subTypes.first;
            _loadForm();
          });
        } else {
          // Multiple sub-types, show sub-type picker
          setState(() {
            _selectedCategoryId = cat.id;
            _selectedSubType = null;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade100,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isWide
            ? Row(
                children: [
                  Icon(cat.icon, color: kNavy, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cat.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: kNavy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cat.description,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(cat.icon, color: kNavy, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    cat.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: kNavy,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cat.description,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
    );
  }

  // ─── Step 2: Pick Sub-Type ───────────────────────────────────────
  Widget _buildSubTypePicker() {
    final cat = kServiceCategories.firstWhere(
      (c) => c.id == _selectedCategoryId,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _selectedCategoryId = null;
                  _selectedSubType = null;
                }),
              ),
              const SizedBox(width: 8),
              Text(
                cat.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 48),
            child: Text(
              'Select the specific service type.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          ...cat.subTypes.map(
            (st) => ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: const Icon(Icons.chevron_right, color: kNavy),
              title: Text(
                st,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                setState(() {
                  _selectedSubType = st;
                  _loadForm();
                });
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              tileColor: Colors.grey.shade50,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 3: Fill Form ──────────────────────────────────────────
  Widget _buildForm() {
    final cat = kServiceCategories.firstWhere(
      (c) => c.id == _selectedCategoryId,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedSubType = null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cat.name} — $_selectedSubType',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                    ),
                    if (cat.isConfidential)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CONFIDENTIAL',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if ({'bass', 'beneficiary'}.contains(_selectedCategoryId)) ...[
            Material(
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.blue.shade100),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _requestingForSomeoneElse,
                      onChanged: _loading
                          ? null
                          : (value) =>
                                _setRequestingForSomeoneElse(value ?? false),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'I am requesting for someone else',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _requestingForSomeoneElse
                                  ? 'Enter the beneficiary or applicant’s information below.'
                                  : 'Unchecked means this request is for yourself. Your name and mobile number are filled in automatically.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ..._fields.where(_isFieldVisible).map((f) => _buildField(f)),
          // BASS document checklist
          if (_bassDocs != null) ...[
            const SizedBox(height: 24),
            const Text(
              'Required Documents',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: kNavy,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload PDF, JPG, or PNG files. Maximum file size: 2 MB each.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...(_bassDocs!).asMap().entries.map((entry) {
              final i = entry.key;
              final doc = entry.value;
              final isApplicable =
                  !doc.requiredWhenRequestingForSomeoneElse ||
                  _requestingForSomeoneElse;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: doc.uploaded
                        ? Colors.green.shade300
                        : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      doc.uploaded
                          ? Icons.check_circle
                          : Icons.upload_file_outlined,
                      color: doc.uploaded ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${doc.name}${doc.required ? ' *' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: doc.required
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          if (doc.fileName != null)
                            Text(
                              '${doc.fileName} · ${_formatFileSize(doc.size ?? 0)}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 11,
                              ),
                            )
                          else
                            Text(
                              !isApplicable
                                  ? 'Not applicable when requesting for yourself'
                                  : doc.required
                                  ? 'Required'
                                  : 'Optional',
                              style: TextStyle(
                                color: doc.required && isApplicable
                                    ? Colors.red
                                    : Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (doc.uploaded)
                      IconButton(
                        tooltip: 'Remove file',
                        onPressed: () => _removeDocument(doc),
                        icon: const Icon(Icons.close, color: Colors.red),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: isApplicable
                            ? () => _pickDocument(doc)
                            : null,
                        icon: Icon(
                          isApplicable ? Icons.attach_file : Icons.block,
                          size: 16,
                        ),
                        label: Text(
                          isApplicable ? 'Choose file' : 'Not applicable',
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          // Info note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'An SMS acknowledgment with your case reference number will be sent to your registered mobile number via Twilio.',
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Confirmation checkbox + Submit
          Row(
            children: [
              Checkbox(
                value: _confirmChecked,
                onChanged: (v) => setState(() => _confirmChecked = v ?? false),
              ),
              const Expanded(
                child: Text(
                  'I confirm that the information I provided is true and accurate to the best of my knowledge.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _confirmChecked && !_loading ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Submit request',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _confirmChecked = false;

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Widget _buildField(FormFieldConfig f) {
    Widget field;
    switch (f.type) {
      case FormFieldType.text:
      case FormFieldType.email:
      case FormFieldType.number:
      case FormFieldType.phone:
        field = TextField(
          controller: _controllers[f.key],
          keyboardType: f.type == FormFieldType.number
              ? TextInputType.number
              : f.type == FormFieldType.phone
              ? TextInputType.phone
              : f.type == FormFieldType.email
              ? TextInputType.emailAddress
              : TextInputType.text,
          onChanged: (_) => _validateField(f),
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            hintText: f.hint,
            border: const OutlineInputBorder(),
            errorText: _fieldErrors[f.key],
          ),
        );
        break;
      case FormFieldType.textarea:
        field = TextField(
          controller: _controllers[f.key],
          maxLines: 3,
          onChanged: (_) => _validateField(f),
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            hintText: f.hint,
            border: const OutlineInputBorder(),
            errorText: _fieldErrors[f.key],
          ),
        );
        break;
      case FormFieldType.dropdown:
        field = DropdownButtonFormField<String>(
          value: _dropdownValues[f.key],
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            border: const OutlineInputBorder(),
            errorText: _fieldErrors[f.key],
          ),
          items: (f.options ?? [])
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, style: const TextStyle(fontSize: 14)),
                ),
              )
              .toList(),
          onChanged: (v) {
            setState(() => _dropdownValues[f.key] = v);
            _validateField(f);
          },
        );
        break;
      case FormFieldType.radio:
        field = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              f.label + (f.required ? ' *' : ''),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              children: (f.options ?? [])
                  .map(
                    (o) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Radio<String>(
                          value: o,
                          groupValue: _radioValues[f.key],
                          onChanged: (v) {
                            setState(() => _radioValues[f.key] = v);
                            _validateField(f);
                          },
                        ),
                        Text(o, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  )
                  .toList(),
            ),
            if (_fieldErrors[f.key] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _fieldErrors[f.key]!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        );
        break;
      case FormFieldType.date:
        field = InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() => _dateValues[f.key] = picked);
              _validateField(f);
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: f.label + (f.required ? ' *' : ''),
              border: const OutlineInputBorder(),
              errorText: _fieldErrors[f.key],
            ),
            child: Text(
              _dateValues[f.key] != null
                  ? '${_dateValues[f.key]!.year}-${_dateValues[f.key]!.month.toString().padLeft(2, '0')}-${_dateValues[f.key]!.day.toString().padLeft(2, '0')}'
                  : 'Select date',
              style: TextStyle(
                color: _dateValues[f.key] != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
        );
        break;
    }

    return Padding(padding: const EdgeInsets.only(bottom: 16), child: field);
  }

  // ─── Confirmation Screen ─────────────────────────────────────────
  Widget _buildConfirmation() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text(
              'Good day! Your request has been successfully submitted.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Case Reference Number:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            Text(
              _refNumber ?? '',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: kNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Date Submitted: ${DateTime.now().toString().split('.').first}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text(
              'We will notify you once there is an update.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text('Thank you!', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _reset,
                child: const Text('Submit Another Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
