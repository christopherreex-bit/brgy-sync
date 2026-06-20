import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  const SubmitRequestScreen({super.key, this.initialCategoryId, this.initialSubType});

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
  bool _isWalkIn = false;

  final _firestore = FirestoreService();
  final _twilio = TwilioService();

  // BASS documents
  List<BassDocument>? _bassDocs;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategoryId != null) {
      _selectedCategoryId = widget.initialCategoryId;
      final cat = kServiceCategories.firstWhere((c) => c.id == _selectedCategoryId);
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
    _fields = formFieldsFor(_selectedCategoryId!, _selectedSubType!);
    _controllers.clear();
    _dropdownValues.clear();
    _radioValues.clear();
    _dateValues.clear();
    for (final f in _fields) {
      _controllers[f.key] = TextEditingController();
      if (f.type == FormFieldType.dropdown) _dropdownValues[f.key] = null;
      if (f.type == FormFieldType.radio) _radioValues[f.key] = null;
      if (f.type == FormFieldType.date) _dateValues[f.key] = null;
    }
    // BASS doc checklist
    if (_selectedCategoryId == 'bass') {
      _bassDocs = kBassDocuments();
    } else {
      _bassDocs = null;
    }
  }

  /// Called externally (from HomeScreen) to set the category.
  void setCategory(String categoryId, {String? subType}) {
    setState(() {
      _selectedCategoryId = categoryId;
      final cat = kServiceCategories.firstWhere((c) => c.id == categoryId);
      _selectedSubType = subType ?? (cat.subTypes.isNotEmpty ? cat.subTypes.first : null);
      _submitted = false;
      _refNumber = null;
      _loadForm();
    });
  }

  Future<void> _submit() async {
    // Validate required fields
    for (final f in _fields) {
      if (!f.required) continue;
      switch (f.type) {
        case FormFieldType.text:
        case FormFieldType.number:
        case FormFieldType.phone:
        case FormFieldType.textarea:
          if (_controllers[f.key]?.text.trim().isEmpty ?? true) {
            _showError('${f.label} is required.');
            return;
          }
          break;
        case FormFieldType.dropdown:
          if (_dropdownValues[f.key] == null) {
            _showError('${f.label} is required.');
            return;
          }
          break;
        case FormFieldType.radio:
          if (_radioValues[f.key] == null) {
            _showError('${f.label} is required.');
            return;
          }
          break;
        case FormFieldType.date:
          if (_dateValues[f.key] == null) {
            _showError('${f.label} is required.');
            return;
          }
          break;
      }
    }

    setState(() => _loading = true);

    try {
      final auth = context.read<AuthService>();
      final user = auth.currentUserModel;
      if (user == null) {
        _showError('Not logged in.');
        setState(() => _loading = false);
        return;
      }

      // Build form data
      final formData = <String, dynamic>{};
      for (final f in _fields) {
        switch (f.type) {
          case FormFieldType.text:
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

      // Documents
      List<Map<String, dynamic>> documents = [];
      if (_bassDocs != null) {
        documents = _bassDocs!.map((d) => {
          'name': d.name,
          'required': d.required,
          'status': d.uploaded ? 'uploaded' : 'missing',
          'storageRef': '',
        }).toList();
      }

      // Compute SLA
      final now = DateTime.now();
      final deadline = sla.computeDeadline(now, _selectedCategoryId!, _selectedSubType!);

      final caseData = CaseModel(
        residentId: user.uid,
        residentName: formData['fullName'] ?? formData['patientName'] ?? formData['studentName'] ?? formData['beneficiaryName'] ?? user.name,
        residentMobile: user.mobile,
        residentAddress: formData['address'] ?? '',
        serviceCategory: _selectedCategoryId!,
        serviceSubType: _selectedSubType!,
        status: 'pending_review',
        submissionChannel: _isWalkIn ? 'walkin' : 'portal',
        submissionTimestamp: now,
        slaDeadline: deadline,
        slaStatus: 'on_time',
        isConfidential: kServiceCategories.firstWhere((c) => c.id == _selectedCategoryId!).isConfidential,
        documents: documents,
        assistanceAmount: formData['assistanceAmount'] != null && formData['assistanceAmount'].toString().isNotEmpty
            ? double.tryParse(formData['assistanceAmount'].toString())
            : null,
      );

      final refNumber = await _firestore.createCase(caseData);
      final smsResult = await _twilio.sendSubmissionAck(user.mobile, refNumber);

      if (mounted) {
        setState(() {
          _loading = false;
          _submitted = true;
          _refNumber = refNumber;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('Submission failed: $e');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
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
      _isWalkIn = false;
    });
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
          const Text('Submit a Request',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Select a service category to begin.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          // Walk-in toggle
          Row(
            children: [
              Checkbox(
                value: _isWalkIn,
                onChanged: (v) => setState(() => _isWalkIn = v ?? false),
              ),
              const Text('Encoding on behalf of resident (walk-in)',
                  style: TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 16),
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
        setState(() {
          _selectedCategoryId = cat.id;
          _selectedSubType = cat.subTypes.isNotEmpty ? cat.subTypes.first : null;
          _loadForm();
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 4, offset: const Offset(0, 2))],
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
                        Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
                        const SizedBox(height: 4),
                        Text(cat.description, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
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
                  Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(cat.description, style: TextStyle(color: Colors.grey.shade600, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
      ),
    );
  }

  // ─── Step 2: Pick Sub-Type ───────────────────────────────────────
  Widget _buildSubTypePicker() {
    final cat = kServiceCategories.firstWhere((c) => c.id == _selectedCategoryId);
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
              Text(cat.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kNavy)),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 48),
            child: Text('Select the specific service type.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          const SizedBox(height: 20),
          ...cat.subTypes.map((st) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const Icon(Icons.chevron_right, color: kNavy),
                title: Text(st, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                onTap: () {
                  setState(() {
                    _selectedSubType = st;
                    _loadForm();
                  });
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tileColor: Colors.grey.shade50,
              )),
        ],
      ),
    );
  }

  // ─── Step 3: Fill Form ──────────────────────────────────────────
  Widget _buildForm() {
    final cat = kServiceCategories.firstWhere((c) => c.id == _selectedCategoryId);
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
                    Text('${cat.name} — $_selectedSubType',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kNavy)),
                    if (cat.isConfidential)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                        child: const Text('CONFIDENTIAL', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ..._fields.map((f) => _buildField(f)),
          // BASS document checklist
          if (_bassDocs != null) ...[
            const SizedBox(height: 24),
            const Text('Required Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kNavy)),
            const SizedBox(height: 4),
            const Text('Check off documents as they are provided.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            ...(_bassDocs!).asMap().entries.map((entry) {
              final i = entry.key;
              final doc = entry.value;
              return CheckboxListTile(
                dense: true,
                value: doc.uploaded,
                onChanged: (v) => setState(() => doc.uploaded = v ?? false),
                title: Text('${i + 1}. ${doc.name}',
                    style: TextStyle(fontSize: 13, fontWeight: doc.required ? FontWeight.w600 : FontWeight.normal)),
                subtitle: doc.required ? const Text('Required', style: TextStyle(color: Colors.red, fontSize: 11)) : null,
                controlAffinity: ListTileControlAffinity.leading,
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
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit request', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  bool _confirmChecked = false;

  Widget _buildField(FormFieldConfig f) {
    Widget field;
    switch (f.type) {
      case FormFieldType.text:
      case FormFieldType.number:
      case FormFieldType.phone:
        field = TextField(
          controller: _controllers[f.key],
          keyboardType: f.type == FormFieldType.number
              ? TextInputType.number
              : f.type == FormFieldType.phone
                  ? TextInputType.phone
                  : TextInputType.text,
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            hintText: f.hint,
            border: const OutlineInputBorder(),
          ),
        );
        break;
      case FormFieldType.textarea:
        field = TextField(
          controller: _controllers[f.key],
          maxLines: 3,
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            hintText: f.hint,
            border: const OutlineInputBorder(),
          ),
        );
        break;
      case FormFieldType.dropdown:
        field = DropdownButtonFormField<String>(
          value: _dropdownValues[f.key],
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            border: const OutlineInputBorder(),
          ),
          items: (f.options ?? []).map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 14)))).toList(),
          onChanged: (v) => setState(() => _dropdownValues[f.key] = v),
        );
        break;
      case FormFieldType.radio:
        field = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label + (f.required ? ' *' : ''), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              children: (f.options ?? []).map((o) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<String>(
                    value: o,
                    groupValue: _radioValues[f.key],
                    onChanged: (v) => setState(() => _radioValues[f.key] = v),
                  ),
                  Text(o, style: const TextStyle(fontSize: 13)),
                ],
              )).toList(),
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
            if (picked != null) setState(() => _dateValues[f.key] = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: f.label + (f.required ? ' *' : ''),
              border: const OutlineInputBorder(),
            ),
            child: Text(
              _dateValues[f.key] != null
                  ? '${_dateValues[f.key]!.year}-${_dateValues[f.key]!.month.toString().padLeft(2, '0')}-${_dateValues[f.key]!.day.toString().padLeft(2, '0')}'
                  : 'Select date',
              style: TextStyle(color: _dateValues[f.key] != null ? Colors.black : Colors.grey),
            ),
          ),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: field,
    );
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
            const Text('Case Reference Number:', style: TextStyle(color: Colors.grey, fontSize: 13)),
            Text(_refNumber ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
            const SizedBox(height: 8),
            Text('Date Submitted: ${DateTime.now().toString().split('.').first}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('We will notify you once there is an update.', style: TextStyle(fontSize: 14)),
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
