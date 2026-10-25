import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/citizen_registry_service.dart';
import '../../services/document_vault_service.dart';
import '../../services/indigency_certificate_service.dart';
import '../../utils/constants.dart';

class CitizenRegistryScreen extends StatefulWidget {
  const CitizenRegistryScreen({super.key});

  @override
  State<CitizenRegistryScreen> createState() => _CitizenRegistryScreenState();
}

class _CitizenRegistryScreenState extends State<CitizenRegistryScreen> {
  final _service = CitizenRegistryService();
  final _indigencyCertificates = IndigencyCertificateService();
  final _search = TextEditingController();
  final _recordsScrollController = ScrollController();
  String _status = 'all';

  @override
  void dispose() {
    _search.dispose();
    _recordsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AuthService>().currentUserModel!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Citizen Registry',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                    ),
                    Text(
                      'Verified resident, household, residency, and socioeconomic records.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _addCitizen(actor),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Add citizen'),
                  ),
                  if (actor.isCaptain)
                    OutlinedButton.icon(
                      onPressed: () => _removeLegacyAccountRecords(actor),
                      icon: const Icon(Icons.person_remove_outlined),
                      label: const Text('Remove account records'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _pendingCorrections(actor),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 720;
              final search = TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search name, mobile, email, or address',
                  border: OutlineInputBorder(),
                ),
              );
              final verification = DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Verification',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All records')),
                  DropdownMenuItem(value: 'verified', child: Text('Verified')),
                  DropdownMenuItem(
                    value: 'unverified',
                    child: Text('Unverified'),
                  ),
                  DropdownMenuItem(
                    value: 'pending_verification',
                    child: Text('Pending verification'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value ?? 'all'),
              );
              if (narrow) {
                return Column(
                  children: [search, const SizedBox(height: 12), verification],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  SizedBox(width: 230, child: verification),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.watchRegistry(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _search.text.trim().toLowerCase();
                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data();
                  if (_status != 'all' &&
                      data['verificationStatus'] != _status) {
                    return false;
                  }
                  final text = [
                    data['legalName'],
                    data['mobile'],
                    data['email'],
                    data['permanentAddress'],
                  ].join(' ').toLowerCase();
                  return query.isEmpty ||
                      query.split(RegExp(r'\s+')).every(text.contains);
                }).toList();
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No registry records found.'),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 800;
                    return Column(
                      children: [
                        if (!compact)
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 30, 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 58),
                                Expanded(flex: 3, child: Text('FULL NAME')),
                                Expanded(flex: 2, child: Text('MOBILE NUMBER')),
                                Expanded(flex: 4, child: Text('ADDRESS')),
                                SizedBox(
                                  width: 150,
                                  child: Text('VERIFICATION'),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: Scrollbar(
                            controller: _recordsScrollController,
                            thumbVisibility: true,
                            interactive: true,
                            child: ListView.separated(
                              controller: _recordsScrollController,
                              padding: const EdgeInsets.only(right: 14),
                              itemCount: docs.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                final data = doc.data();
                                final name =
                                    (data['legalName'] ??
                                            data['fullName'] ??
                                            data['name'] ??
                                            'Unnamed resident')
                                        .toString();
                                final mobile = (data['mobile'] ?? 'No mobile')
                                    .toString();
                                final address =
                                    (data['permanentAddress'] ??
                                            'Address not recorded')
                                        .toString();
                                final status = _statusLabel(
                                  (data['verificationStatus'] ?? 'unverified')
                                      .toString(),
                                );
                                if (compact) {
                                  return ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.badge_outlined),
                                    ),
                                    title: Text(name),
                                    subtitle: Text('$mobile · $address'),
                                    trailing: Chip(label: Text(status)),
                                    onTap: () =>
                                        _editRecord(doc.id, data, actor),
                                  );
                                }
                                return InkWell(
                                  onTap: () => _editRecord(doc.id, data, actor),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      12,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 58,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: CircleAvatar(
                                              child: Icon(Icons.badge_outlined),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            mobile,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 4,
                                          child: Text(
                                            address,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 150,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Chip(label: Text(status)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
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

  Widget _pendingCorrections(UserModel actor) {
    if (!actor.isOfficer && !actor.isCaptain) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchPendingCorrections(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          collapsedBackgroundColor: Colors.orange.shade50,
          title: Text(
            '${docs.length} pending registry correction${docs.length == 1 ? '' : 's'}',
          ),
          children: docs.map((doc) {
            final data = doc.data();
            return ListTile(
              title: Text((data['residentName'] ?? 'Resident').toString()),
              subtitle: Text(
                '${data['requestedChanges']}\nReason: ${data['reason'] ?? ''}',
              ),
              isThreeLine: true,
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _resolve(doc.id, actor, true),
                  ),
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _resolve(doc.id, actor, false),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _removeLegacyAccountRecords(UserModel actor) async {
    if (!actor.isCaptain) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove account-imported records?'),
        content: const Text(
          'This permanently removes only legacy Citizen Registry records linked '
          'to resident login accounts. Independent manual records and generated '
          'sample citizens will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove legacy records'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await _service.removeAccountDerivedRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count account-imported records removed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove records: $error')),
        );
      }
    }
  }

  Future<void> _addCitizen(UserModel actor) async {
    final mobileController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? availabilityError;
    var checkingAvailability = false;
    final mobile = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add citizen'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: mobileController,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 11,
              onChanged: (_) {
                if (availabilityError != null) {
                  setDialogState(() => availabilityError = null);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Unique mobile number',
                hintText: '09XXXXXXXXX',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (!RegExp(r'^09\d{9}$').hasMatch(value ?? '')) {
                  return 'Use 09XXXXXXXXX (11 digits).';
                }
                return availabilityError;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: checkingAvailability
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: checkingAvailability
                  ? null
                  : () async {
                      setDialogState(() => availabilityError = null);
                      if (formKey.currentState?.validate() != true) return;
                      setDialogState(() => checkingAvailability = true);
                      try {
                        final value = mobileController.text.trim();
                        final existing = await _service.findByMobile(value);
                        if (!dialogContext.mounted) return;
                        if (existing != null) {
                          setDialogState(() {
                            checkingAvailability = false;
                            availabilityError =
                                'This mobile number is already in the registry.';
                          });
                          formKey.currentState?.validate();
                          return;
                        }
                        Navigator.pop(dialogContext, value);
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          checkingAvailability = false;
                          availabilityError =
                              'Could not check the mobile number. Try again.';
                        });
                        formKey.currentState?.validate();
                      }
                    },
              child: checkingAvailability
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    // Let the first dialog finish its reverse transition before disposing its
    // controller or presenting the full record editor.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    mobileController.dispose();
    if (mobile == null || !mounted) return;
    await _editRecord(mobile, {'mobile': mobile}, actor);
  }

  Future<void> _resolve(String id, UserModel actor, bool approve) async {
    await _service.resolveCorrection(
      correctionId: id,
      reviewer: actor,
      approve: approve,
      rejectionReason: approve
          ? ''
          : 'Correction request rejected after review.',
    );
  }

  Future<void> _editRecord(
    String id,
    Map<String, dynamic> data,
    UserModel actor,
  ) async {
    const fields = <String, String>{
      'legalName': 'Full legal name',
      'dateOfBirth': 'Date of birth (YYYY-MM-DD)',
      'sex': 'Sex',
      'civilStatus': 'Civil status',
      'nationality': 'Nationality',
      'houseLotNumber': 'House/Lot No.',
      'street': 'Street',
      'barangay': 'Barangay / Area',
      'city': 'City',
      'postalCode': 'Postal code',
      'permanentAddress': 'Permanent address',
      'temporaryAddress': 'Temporary address',
      'residencySince': 'Resident since',
      'mobile': 'Mobile number',
      'email': 'Email address',
      'householdId': 'Household ID',
      'familyComposition': 'Family composition',
      'dependencies': 'Dependencies',
      'employmentStatus': 'Employment status',
      'occupation': 'Occupation',
      'incomeBracket': 'Household income bracket',
      'classificationsText': 'Classifications (comma-separated)',
      'voterStatus': 'Registered voter status',
      'precinctNumber': 'Precinct number',
      'emergencyContactName': 'Emergency contact name',
      'emergencyContactMobile': 'Emergency contact mobile',
      'emergencyContactRelationship': 'Emergency contact relationship',
    };
    const dropdownOptions = <String, List<String>>{
      'sex': ['Male', 'Female', 'Prefer not to say'],
      'civilStatus': ['Single', 'Married', 'Widowed', 'Separated'],
      'employmentStatus': [
        'Employed',
        'Self-employed',
        'Unemployed',
        'Student',
        'Retired',
      ],
      'incomeBracket': [
        'Below ₱10,000',
        '₱10,000–₱19,999',
        '₱20,000–₱39,999',
        '₱40,000 and above',
        'Prefer not to say',
      ],
      'voterStatus': ['Registered', 'Not registered'],
    };
    final controllers = {
      for (final entry in fields.entries)
        entry.key: TextEditingController(
          text: entry.key == 'classificationsText'
              ? ((data['classifications'] as List?) ?? const []).join(', ')
              : (data[entry.key] ?? '').toString(),
        ),
    };
    const sections = <Map<String, Object>>[
      {
        'title': 'Personal information',
        'icon': Icons.person_outline,
        'keys': [
          'legalName',
          'dateOfBirth',
          'sex',
          'civilStatus',
          'nationality',
        ],
      },
      {
        'title': 'Residency and contact',
        'icon': Icons.home_outlined,
        'keys': [
          'houseLotNumber',
          'street',
          'barangay',
          'city',
          'postalCode',
          'permanentAddress',
          'temporaryAddress',
          'residencySince',
          'mobile',
          'email',
        ],
      },
      {
        'title': 'Household and socioeconomic information',
        'icon': Icons.groups_outlined,
        'keys': [
          'householdId',
          'familyComposition',
          'dependencies',
          'employmentStatus',
          'occupation',
          'incomeBracket',
        ],
      },
      {
        'title': 'Classification and voter information',
        'icon': Icons.how_to_vote_outlined,
        'keys': ['classificationsText', 'voterStatus', 'precinctNumber'],
      },
      {
        'title': 'Emergency contact',
        'icon': Icons.contact_emergency_outlined,
        'keys': [
          'emergencyContactName',
          'emergencyContactMobile',
          'emergencyContactRelationship',
        ],
      },
    ];
    final formKey = GlobalKey<FormState>();
    final editorScrollController = ScrollController();
    final residentMobile = (data['mobile'] ?? '').toString();

    String? validateField(String key, String? rawValue) {
      final value = (rawValue ?? '').trim();
      if (key == 'legalName' && value.isEmpty) {
        return 'Full legal name is required.';
      }
      if (key == 'mobile') {
        if (value.isEmpty) return 'Mobile number is required.';
        if (!RegExp(r'^09\d{9}$').hasMatch(value)) {
          return 'Use 09XXXXXXXXX (11 digits).';
        }
      }
      if (key == 'emergencyContactMobile' &&
          value.isNotEmpty &&
          !RegExp(r'^09\d{9}$').hasMatch(value)) {
        return 'Use 09XXXXXXXXX (11 digits).';
      }
      if (key == 'email') {
        if (value.isEmpty) return 'Email address is required.';
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
          return 'Enter a valid email address.';
        }
      }
      if (key == 'postalCode' &&
          value.isNotEmpty &&
          !RegExp(r'^\d{4}$').hasMatch(value)) {
        return 'Postal code must contain 4 digits.';
      }
      if ({'houseLotNumber', 'dependencies'}.contains(key) &&
          value.isNotEmpty &&
          !RegExp(r'^\d+$').hasMatch(value)) {
        return 'Numbers only.';
      }
      if ({'dateOfBirth', 'residencySince'}.contains(key) && value.isNotEmpty) {
        final date = DateTime.tryParse(value);
        if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
          return 'Use YYYY-MM-DD.';
        }
        final parts = value.split('-').map(int.parse).toList();
        if (date.year != parts[0] ||
            date.month != parts[1] ||
            date.day != parts[2]) {
          return 'Enter a valid calendar date.';
        }
        if (date.isAfter(DateTime.now())) {
          return 'Date cannot be in the future.';
        }
      }
      return null;
    }

    List<TextInputFormatter>? inputFormattersFor(String key) {
      if ({
        'houseLotNumber',
        'postalCode',
        'mobile',
        'emergencyContactMobile',
        'dependencies',
      }.contains(key)) {
        return [FilteringTextInputFormatter.digitsOnly];
      }
      return null;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
        contentPadding: const EdgeInsets.fromLTRB(28, 14, 18, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Citizen registry record'),
            SizedBox(height: 4),
            Text(
              'Complete the available information. Empty fields may be updated later.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 760,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 620),
            child: Scrollbar(
              controller: editorScrollController,
              thumbVisibility: true,
              interactive: true,
              child: SingleChildScrollView(
                controller: editorScrollController,
                padding: const EdgeInsets.fromLTRB(0, 8, 14, 8),
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      ...sections.map((section) {
                        final title = section['title']! as String;
                        final icon = section['icon']! as IconData;
                        final keys = section['keys']! as List<String>;
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 20, color: kNavy),
                                  const SizedBox(width: 8),
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: kNavy,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final fieldWidth = constraints.maxWidth < 620
                                      ? constraints.maxWidth
                                      : (constraints.maxWidth - 12) / 2;
                                  return Wrap(
                                    spacing: 12,
                                    runSpacing: 16,
                                    children: keys.map((key) {
                                      final isLongText =
                                          key.contains('Address') ||
                                          key == 'familyComposition' ||
                                          key == 'dependencies';
                                      final isDateField = {
                                        'dateOfBirth',
                                        'residencySince',
                                      }.contains(key);
                                      final options = dropdownOptions[key];
                                      final currentValue = controllers[key]!
                                          .text
                                          .trim();
                                      final selectedOption = options
                                          ?.where(
                                            (option) =>
                                                option.toLowerCase() ==
                                                currentValue.toLowerCase(),
                                          )
                                          .firstOrNull;
                                      return SizedBox(
                                        width: fieldWidth,
                                        child: options != null
                                            ? DropdownButtonFormField<String>(
                                                initialValue: selectedOption,
                                                isExpanded: true,
                                                decoration: InputDecoration(
                                                  labelText: fields[key],
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border:
                                                      const OutlineInputBorder(),
                                                ),
                                                items: options
                                                    .map(
                                                      (option) =>
                                                          DropdownMenuItem(
                                                            value: option,
                                                            child: Text(option),
                                                          ),
                                                    )
                                                    .toList(),
                                                onChanged: (value) =>
                                                    controllers[key]!.text =
                                                        value ?? '',
                                              )
                                            : TextFormField(
                                                controller: controllers[key],
                                                readOnly: isDateField,
                                                onTap: isDateField
                                                    ? () async {
                                                        final today =
                                                            DateTime.now();
                                                        final enteredDate =
                                                            DateTime.tryParse(
                                                              controllers[key]!
                                                                  .text
                                                                  .trim(),
                                                            );
                                                        final initialDate =
                                                            enteredDate !=
                                                                    null &&
                                                                !enteredDate
                                                                    .isAfter(
                                                                      today,
                                                                    )
                                                            ? enteredDate
                                                            : today;
                                                        final selected =
                                                            await showDatePicker(
                                                              context: context,
                                                              initialDate:
                                                                  initialDate,
                                                              firstDate:
                                                                  DateTime(
                                                                    1900,
                                                                  ),
                                                              lastDate: today,
                                                              helpText:
                                                                  key ==
                                                                      'dateOfBirth'
                                                                  ? 'Select date of birth'
                                                                  : 'Select residency start date',
                                                            );
                                                        if (selected != null) {
                                                          controllers[key]!
                                                                  .text =
                                                              '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
                                                        }
                                                      }
                                                    : null,
                                                minLines: 1,
                                                maxLines: isLongText ? 2 : 1,
                                                keyboardType:
                                                    {
                                                      'houseLotNumber',
                                                      'postalCode',
                                                      'mobile',
                                                      'emergencyContactMobile',
                                                      'dependencies',
                                                    }.contains(key)
                                                    ? TextInputType.number
                                                    : key == 'email'
                                                    ? TextInputType.emailAddress
                                                    : null,
                                                inputFormatters:
                                                    inputFormattersFor(key),
                                                validator: (value) =>
                                                    validateField(key, value),
                                                autovalidateMode:
                                                    AutovalidateMode
                                                        .onUserInteraction,
                                                decoration: InputDecoration(
                                                  labelText: fields[key],
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  helperText:
                                                      key == 'houseLotNumber'
                                                      ? 'Numbers only'
                                                      : key == 'postalCode'
                                                      ? '4 digits'
                                                      : null,
                                                  suffixIcon: isDateField
                                                      ? const Icon(
                                                          Icons.calendar_month,
                                                        )
                                                      : null,
                                                  border:
                                                      const OutlineInputBorder(),
                                                ),
                                              ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                      _indigencyCertificatePanel(id, data, actor),
                      const SizedBox(height: 12),
                      _requestHistory(residentMobile),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(context, true);
              }
            },
            child: Text(
              actor.isOfficer || actor.isCaptain
                  ? 'Save & verify'
                  : 'Submit for verification',
            ),
          ),
        ],
      ),
    );
    editorScrollController.dispose();
    if (saved == true) {
      if (controllers['permanentAddress']!.text.trim().isEmpty) {
        controllers['permanentAddress']!.text = [
          controllers['houseLotNumber']!.text.trim(),
          controllers['street']!.text.trim(),
          controllers['barangay']!.text.trim(),
          controllers['city']!.text.trim(),
          controllers['postalCode']!.text.trim(),
        ].where((part) => part.isNotEmpty).join(', ');
      }
      final values = <String, dynamic>{
        for (final entry in controllers.entries)
          if (entry.key != 'classificationsText')
            entry.key: entry.value.text.trim(),
        'classifications': controllers['classificationsText']!.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      };
      try {
        await _service.saveRecord(
          registryId: id,
          values: values,
          actor: actor,
          verify: actor.isOfficer || actor.isCaptain,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Citizen record saved.')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save record: $error')),
          );
        }
      }
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Widget _indigencyCertificatePanel(
    String registryId,
    Map<String, dynamic> citizen,
    UserModel actor,
  ) {
    final verified = citizen['verificationStatus'] == 'verified';
    final documentId = DocumentVaultService.documentKey(
      'Barangay Certificate of Indigency',
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('citizenRegistry')
            .doc(registryId)
            .collection('verifiedDocuments')
            .doc(documentId)
            .snapshots(),
        builder: (context, snapshot) {
          final document = snapshot.data?.data();
          final validUntil = document?['validUntil'];
          final expiry = validUntil is Timestamp ? validUntil.toDate() : null;
          final valid =
              document?['verificationStatus'] == 'verified' &&
              expiry != null &&
              !expiry.isBefore(DateTime.now());
          final certificateNumber = (document?['certificateNumber'] ?? '')
              .toString();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_outlined, color: kNavy),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Certificate of Indigency',
                      style: TextStyle(
                        color: kNavy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (valid)
                    Chip(
                      avatar: const Icon(Icons.verified, size: 16),
                      label: const Text('Valid'),
                      backgroundColor: Colors.green.shade100,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                !verified
                    ? 'Verify this citizen record before generating an official certificate.'
                    : valid
                    ? '$certificateNumber · Valid until ${_formatRegistryDate(expiry)}'
                    : document == null
                    ? 'No system-generated certificate is on file.'
                    : 'The previous certificate expired on ${_formatRegistryDate(expiry)}.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: verified
                        ? () => _generateIndigencyCertificate(
                            registryId,
                            citizen,
                            actor,
                          )
                        : null,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      document == null
                          ? 'Generate certificate'
                          : 'Regenerate certificate',
                    ),
                  ),
                  if (document != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _indigencyCertificates.previewStored(document);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Could not open certificate: $error',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview / print'),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatRegistryDate(DateTime? date) {
    if (date == null) return 'unknown date';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _generateIndigencyCertificate(
    String registryId,
    Map<String, dynamic> citizen,
    UserModel actor,
  ) async {
    final reasonController = TextEditingController(
      text: 'Medical/Financial Assistance from MAO',
    );
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Generate Certificate of Indigency'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${citizen['legalName'] ?? ''}\n${citizen['permanentAddress'] ?? ''}',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for issuance',
                  helperText: 'This wording will appear on the certificate.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'The certificate will be valid for 60 days and saved as a verified reusable document.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;
    try {
      await _indigencyCertificates.generateAndStore(
        registryId: registryId,
        citizen: citizen,
        actor: actor,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Certificate generated and saved to the Citizen Registry.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate certificate: $error')),
        );
      }
    }
  }

  String _statusLabel(String value) => switch (value) {
    'verified' => 'Verified',
    'pending_verification' => 'Pending verification',
    _ => 'Unverified',
  };

  Widget _requestHistory(String residentId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.blueGrey.shade50,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.blueGrey.shade100),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _service.watchResidentRequests(residentId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Row(
                children: [
                  Icon(Icons.history, color: kNavy),
                  SizedBox(width: 10),
                  Expanded(child: Text('Request history could not be loaded.')),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Row(
                children: [
                  Icon(Icons.history, color: kNavy),
                  SizedBox(width: 10),
                  Expanded(child: Text('Loading request history…')),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              );
            }
            final requests = [...snapshot.data!.docs]
              ..sort((a, b) {
                final aDate = a.data()['submissionTimestamp'];
                final bDate = b.data()['submissionTimestamp'];
                final aMillis = aDate is Timestamp
                    ? aDate.millisecondsSinceEpoch
                    : 0;
                final bMillis = bDate is Timestamp
                    ? bDate.millisecondsSinceEpoch
                    : 0;
                return bMillis.compareTo(aMillis);
              });
            return ExpansionTile(
              leading: const Icon(Icons.history, color: kNavy),
              title: const Text(
                'Request history',
                style: TextStyle(
                  color: kNavy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                requests.isEmpty
                    ? 'No requests recorded for this resident.'
                    : '${requests.length} request${requests.length == 1 ? '' : 's'} recorded',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: requests.isEmpty
                  ? const []
                  : requests.map((request) {
                      final caseData = request.data();
                      final reference =
                          (caseData['referenceNumber'] ?? request.id)
                              .toString();
                      final service =
                          (caseData['serviceSubType'] ?? 'Service request')
                              .toString();
                      final status = _caseStatusLabel(caseData['status']);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Material(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.blueGrey.shade100),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            leading: const Icon(
                              Icons.description_outlined,
                              color: kNavy,
                            ),
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reference,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: kNavy,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        service,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 130,
                                  child: Center(
                                    child: Chip(
                                      label: SizedBox(
                                        width: 96,
                                        child: Text(
                                          status,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              12,
                            ),
                            children: [
                              _caseActionHistory(request.id, caseData),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _caseActionHistory(String caseId, Map<String, dynamic> caseData) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchCaseActionLog(caseId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Text('Case history could not be loaded.'),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final logs = [...snapshot.data!.docs]
          ..sort((a, b) {
            final aTimestamp = a.data()['timestamp'];
            final bTimestamp = b.data()['timestamp'];
            final aMillis = aTimestamp is Timestamp
                ? aTimestamp.millisecondsSinceEpoch
                : 0;
            final bMillis = bTimestamp is Timestamp
                ? bTimestamp.millisecondsSinceEpoch
                : 0;
            return bMillis.compareTo(aMillis);
          });
        final submitted = caseData['submissionTimestamp'];
        return Column(
          children: [
            if (logs.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No status changes have been recorded yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ...logs.map((logDocument) {
              final log = logDocument.data();
              final timestamp = log['timestamp'];
              final action = (log['action'] ?? 'Case updated').toString();
              final notes = (log['notes'] ?? '').toString().trim();
              final staffName = (log['staffName'] ?? '').toString().trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5),
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
                          Text(
                            action,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (notes.isNotEmpty) Text(notes),
                          Text(
                            [
                              if (staffName.isNotEmpty) staffName,
                              if (timestamp is Timestamp)
                                _formatHistoryDate(timestamp.toDate()),
                            ].join(' · '),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (submitted is Timestamp)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Request submitted · ${_formatHistoryDate(submitted.toDate())}',
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  String _formatHistoryDate(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:$minute $period';
  }

  String _caseStatusLabel(dynamic value) {
    final normalized = (value ?? 'unknown').toString().replaceAll('_', ' ');
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
