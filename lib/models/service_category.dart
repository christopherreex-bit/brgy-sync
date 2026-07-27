import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Defines all 7 service categories, their subtypes, SLA mappings,
/// and form field configurations for the dynamic form builder.

// ─── SLA defaults (working days unless noted) ──────────────────────
const Map<String, Map<String, dynamic>> kSlaDefaults = {
  'documents': {'value': 15, 'unit': 'minutes'},
  'bass_standard': {'value': 3, 'unit': 'working_days'},
  'bass_medical': {'value': 5, 'unit': 'working_days'},
  'vaw': {'value': 1, 'unit': 'working_days'},
  'community': {'value': 3, 'unit': 'working_days'},
  'beneficiary': {'value': 3, 'unit': 'working_days'},
  'education': {'value': 5, 'unit': 'working_days'},
  'adhoc': {'value': 5, 'unit': 'working_days'},
};

/// Returns the SLA config key for a given category + sub-type.
String slaKeyFor(String category, String subType) {
  if (category.trim().toLowerCase() == 'bass') {
    final normalizedSubType = subType.trim().toLowerCase();
    final isMedical =
        normalizedSubType.contains('dialysis') ||
        normalizedSubType.contains('chemotherapy') ||
        normalizedSubType.contains('major operation');
    return isMedical ? 'bass_medical' : 'bass_standard';
  }
  switch (category) {
    case 'documents':
      return 'documents';
    case 'vaw':
      return 'vaw';
    case 'community':
      return 'community';
    case 'beneficiary':
      return 'beneficiary';
    case 'education':
      return 'education';
    case 'adhoc':
      return 'adhoc';
    default:
      return 'documents';
  }
}

// ─── Service Category ──────────────────────────────────────────────
class ServiceCategory {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<String> subTypes;
  final bool isConfidential;

  const ServiceCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.subTypes,
    this.isConfidential = false,
  });
}

const List<ServiceCategory> kServiceCategories = [
  ServiceCategory(
    id: 'bass',
    name: 'BASS Assistance',
    description: 'Medical, burial, rehab, fire relief',
    icon: Icons.work,
    subTypes: [
      'Medical – Dialysis',
      'Medical – Chemotherapy',
      'Medical – Major Operations',
      'Burial Assistance',
      'Drug Rehabilitation',
      'Fire Relief',
    ],
  ),
  ServiceCategory(
    id: 'documents',
    name: 'Barangay Documents',
    description: 'Clearance, indigency cert, brgy ID',
    icon: Icons.description,
    subTypes: ['Barangay Clearance', 'Indigency Certificate', 'Barangay ID'],
  ),
  ServiceCategory(
    id: 'community',
    name: 'Community Services',
    description: 'Infrastructure, equipment loan',
    icon: Icons.build,
    subTypes: ['Infrastructure Concern', 'Equipment Loan'],
  ),
  ServiceCategory(
    id: 'beneficiary',
    name: 'Beneficiary Registration',
    description: 'Senior citizen & PWD programs',
    icon: Icons.groups,
    subTypes: ['Senior Citizen Birthday Program', 'PWD Birthday Program'],
  ),
  ServiceCategory(
    id: 'vaw',
    name: 'VAW / BCPC Report',
    description: 'Case report, child protection',
    icon: Icons.shield,
    subTypes: ['VAW Desk Report', 'BCPC Child Protection Case'],
    isConfidential: true,
  ),
  ServiceCategory(
    id: 'education',
    name: 'Education Incentive',
    description: 'Honor student application',
    icon: Icons.school,
    subTypes: ['Honor Student Application'],
  ),
  ServiceCategory(
    id: 'adhoc',
    name: 'Ad Hoc / Special Program',
    description: 'One-time distributions or irregular community initiatives',
    icon: Icons.calendar_month,
    subTypes: [
      'One-Time Distribution',
      'Special Assistance Program',
      'Irregular Community Initiative',
    ],
  ),
];

// ─── Form Field Config ─────────────────────────────────────────────
enum FormFieldType {
  text,
  number,
  date,
  dropdown,
  radio,
  textarea,
  phone,
  email,
}

class FormFieldConfig {
  final String key;
  final String label;
  final FormFieldType type;
  final bool required;
  final List<String>? options; // for dropdown / radio
  final String? hint;
  final String? validationPattern; // regex pattern for validation
  final String? validationMessage; // custom error message
  final int? minAge; // for date fields: minimum age in years

  const FormFieldConfig({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.options,
    this.hint,
    this.validationPattern,
    this.validationMessage,
    this.minAge,
  });
}

/// Returns the list of form fields for a given service sub-type.
List<FormFieldConfig> formFieldsFor(String categoryId, String subType) {
  switch (categoryId) {
    case 'documents':
      return _documentFields(subType);
    case 'bass':
      return _bassFields();
    case 'community':
      return _communityFields(subType);
    case 'beneficiary':
      return _beneficiaryFields(subType);
    case 'vaw':
      return _vawFields(subType);
    case 'education':
      return _educationFields();
    case 'adhoc':
      return _adhocFields(subType);
    default:
      return _genericFields();
  }
}

List<FormFieldConfig> _documentFields(String subType) {
  switch (subType) {
    case 'Indigency Certificate':
      return const [
        FormFieldConfig(
          key: 'beneficiaryName',
          label: 'Name of Beneficiary/Patient',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'guardianName',
          label: 'Name of Guardian/Claimant',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'address',
          label: 'Address',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'relationship',
          label: 'Relationship to Beneficiary/Patient',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'purpose',
          label: 'Purpose',
          type: FormFieldType.textarea,
          required: true,
        ),
      ];
    case 'Barangay ID':
      return const [
        FormFieldConfig(
          key: 'surname',
          label: 'Surname',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'firstName',
          label: 'First Name',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'middleInitial',
          label: 'Middle Initial',
          type: FormFieldType.text,
        ),
        FormFieldConfig(
          key: 'address',
          label: 'Address',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'birthplace',
          label: 'Birthplace',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'birthday',
          label: 'Birthday',
          type: FormFieldType.date,
          required: true,
          minAge: 15,
        ),
        FormFieldConfig(
          key: 'gender',
          label: 'Gender',
          type: FormFieldType.radio,
          required: true,
          options: ['Male', 'Female'],
        ),
        FormFieldConfig(
          key: 'precinct',
          label: "Voter's Precinct No.",
          type: FormFieldType.text,
        ),
        FormFieldConfig(
          key: 'contact',
          label: 'Contact No.',
          type: FormFieldType.phone,
          required: true,
          hint: '09XXXXXXXXX',
        ),
        FormFieldConfig(
          key: 'lengthOfStay',
          label: 'Length of Stay in Barangay',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'civilStatus',
          label: 'Civil Status',
          type: FormFieldType.dropdown,
          required: true,
          options: ['Single', 'Married', 'Widowed', 'Separated'],
        ),
        FormFieldConfig(
          key: 'emergencyName',
          label: 'Person to Contact in Case of Emergency: Name',
          type: FormFieldType.text,
        ),
        FormFieldConfig(
          key: 'emergencyContact',
          label: 'Emergency Contact No.',
          type: FormFieldType.phone,
        ),
        FormFieldConfig(
          key: 'emergencyRelation',
          label: 'Emergency Relation',
          type: FormFieldType.text,
        ),
      ];
    case 'Barangay Clearance':
      return const [
        FormFieldConfig(
          key: 'fullName',
          label: 'Full Name / Pangalan',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'nickname',
          label: 'Nickname',
          type: FormFieldType.text,
        ),
        FormFieldConfig(
          key: 'address',
          label: 'Address / Tirahan',
          type: FormFieldType.text,
          required: true,
        ),
        FormFieldConfig(
          key: 'gender',
          label: 'Gender / Babae o Lalaki',
          type: FormFieldType.radio,
          required: true,
          options: ['Male', 'Female'],
        ),
        FormFieldConfig(
          key: 'birthday',
          label: 'Birthday / Kaarawan',
          type: FormFieldType.date,
          required: true,
          minAge: 18,
        ),
        FormFieldConfig(
          key: 'civilStatus',
          label: 'Civil Status',
          type: FormFieldType.dropdown,
          required: true,
          options: ['Single', 'Married', 'Widowed', 'Separated'],
        ),
        FormFieldConfig(
          key: 'yearsResidency',
          label: 'Years of Residency in Calzada',
          type: FormFieldType.number,
          required: true,
        ),
        FormFieldConfig(
          key: 'purpose',
          label: 'Purpose of Clearance / Saan Gagamitin ang Brgy. Clearance',
          type: FormFieldType.textarea,
          required: true,
        ),
      ];
    default:
      return _genericFields();
  }
}

List<FormFieldConfig> _bassFields() {
  return const [
    FormFieldConfig(
      key: 'patientName',
      label: 'Patient/Beneficiary Name',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'claimantName',
      label: 'Claimant Name',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'address',
      label: 'Address',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'contact',
      label: 'Contact No.',
      type: FormFieldType.phone,
      required: true,
      hint: '09XXXXXXXXX',
    ),
    FormFieldConfig(
      key: 'relationship',
      label: 'Relationship to Patient',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'purpose',
      label: 'Purpose / Details',
      type: FormFieldType.textarea,
      required: true,
    ),
    FormFieldConfig(
      key: 'assistanceAmount',
      label: 'Assistance Amount (₱)',
      type: FormFieldType.number,
      required: true,
    ),
  ];
}

List<FormFieldConfig> _communityFields(String subType) {
  return const [
    FormFieldConfig(
      key: 'fullName',
      label: 'Full Name',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'address',
      label: 'Address',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'contact',
      label: 'Contact No.',
      type: FormFieldType.phone,
      required: true,
      hint: '09XXXXXXXXX',
    ),
    FormFieldConfig(
      key: 'details',
      label: 'Details / Description',
      type: FormFieldType.textarea,
      required: true,
    ),
  ];
}

List<FormFieldConfig> _beneficiaryFields(String subType) {
  final minimumAge = subType == 'Senior Citizen Birthday Program' ? 60 : null;

  return [
    FormFieldConfig(
      key: 'fullName',
      label: 'Full Name',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'address',
      label: 'Address',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'contact',
      label: 'Contact No.',
      type: FormFieldType.phone,
      required: true,
      hint: '09XXXXXXXXX',
    ),
    FormFieldConfig(
      key: 'requesterRelationship',
      label: 'Your Relationship to the Beneficiary',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'birthday',
      label: 'Birthday',
      type: FormFieldType.date,
      required: true,
      minAge: minimumAge,
    ),
    FormFieldConfig(
      key: 'gender',
      label: 'Gender',
      type: FormFieldType.radio,
      required: true,
      options: ['Male', 'Female'],
    ),
  ];
}

List<FormFieldConfig> _vawFields(String subType) {
  return const [
    FormFieldConfig(
      key: 'reporterName',
      label: 'Reporter Name (optional — may be anonymous)',
      type: FormFieldType.text,
    ),
    FormFieldConfig(
      key: 'address',
      label: 'Address',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'contact',
      label: 'Contact No.',
      type: FormFieldType.phone,
      hint: '09XXXXXXXXX',
    ),
    FormFieldConfig(
      key: 'incidentDetails',
      label: 'Incident Details',
      type: FormFieldType.textarea,
      required: true,
    ),
    FormFieldConfig(
      key: 'actionRequested',
      label: 'Action Requested',
      type: FormFieldType.textarea,
      required: true,
    ),
  ];
}

List<FormFieldConfig> _educationFields() {
  return const [
    FormFieldConfig(
      key: 'studentName',
      label: 'Student Name',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'address',
      label: 'Address',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'contact',
      label: 'Contact No.',
      type: FormFieldType.phone,
      required: true,
      hint: '09XXXXXXXXX',
    ),
    FormFieldConfig(
      key: 'school',
      label: 'School',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'gradeLevel',
      label: 'Grade Level',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'guardianName',
      label: 'Parent/Guardian Name',
      type: FormFieldType.text,
      required: true,
    ),
  ];
}

List<FormFieldConfig> _adhocFields(String subType) {
  return const [
    FormFieldConfig(
      key: 'fullName',
      label: 'Full Name',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'address',
      label: 'Address',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'contact',
      label: 'Contact No.',
      type: FormFieldType.phone,
      required: true,
      hint: '09XXXXXXXXX',
    ),
    FormFieldConfig(
      key: 'details',
      label: 'Details / Description',
      type: FormFieldType.textarea,
      required: true,
    ),
  ];
}

List<FormFieldConfig> _genericFields() {
  return const [
    FormFieldConfig(
      key: 'fullName',
      label: 'Full Name',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'address',
      label: 'Address',
      type: FormFieldType.text,
      required: true,
    ),
    FormFieldConfig(
      key: 'contact',
      label: 'Contact No.',
      type: FormFieldType.phone,
      required: true,
      hint: '09XXXXXXXXX',
    ),
    FormFieldConfig(
      key: 'details',
      label: 'Details',
      type: FormFieldType.textarea,
      required: true,
    ),
  ];
}

// ─── BASS Document Checklist ───────────────────────────────────────
class BassDocument {
  final String name;
  bool required;
  final bool requiredWhenRequestingForSomeoneElse;
  bool uploaded;
  String? fileName;
  String? contentType;
  int? size;
  Uint8List? bytes;

  BassDocument({
    required this.name,
    this.required = true,
    this.requiredWhenRequestingForSomeoneElse = false,
    this.uploaded = false,
    this.fileName,
    this.contentType,
    this.size,
    this.bytes,
  });
}

List<BassDocument> kBassDocuments(String subType) => [
  if (slaKeyFor('bass', subType) == 'bass_medical')
    BassDocument(name: 'Certificate of Admission', required: true),
  BassDocument(
    name: "Medical Abstract / Doctor's Certificate / Death Certificate",
    required: true,
  ),
  BassDocument(
    name: "Voter's Certificate from Comelec (patient)",
    required: true,
  ),
  BassDocument(
    name: "Voter's Certificate from Comelec (claimant)",
    required: true,
  ),
  BassDocument(name: "Barangay Certificate of Indigency", required: true),
  BassDocument(name: "Valid ID (patient)", required: true),
  BassDocument(name: "Valid ID (claimant)", required: true),
  BassDocument(
    name: "Proof of relationship to patient / demised",
    required: false,
    requiredWhenRequestingForSomeoneElse: true,
  ),
  BassDocument(name: "Picture of patient (Whole Body)", required: true),
  BassDocument(name: "House sketch (for medical cases)", required: false),
];

// ─── Validation Helpers ───────────────────────────────────────────────
/// Philippine mobile number pattern: 09XXXXXXXXX (11 digits starting with 09)
const String kPhonePattern = r'^09\d{9}$';

/// Email pattern
const String kEmailPattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';

/// Validates a phone number against Philippine format
bool validatePhone(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  return RegExp(kPhonePattern).hasMatch(value.trim());
}

/// Validates an email address
bool validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  return RegExp(kEmailPattern).hasMatch(value.trim());
}

/// Validates a numeric string
bool validateNumber(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  return double.tryParse(value.trim()) != null;
}

/// Validates a date meets minimum age requirement
bool validateMinAge(DateTime? date, int minAge) {
  if (date == null) return false;
  final now = DateTime.now();
  int age = now.year - date.year;
  if (now.month < date.month ||
      (now.month == date.month && now.day < date.day)) {
    age--;
  }
  return age >= minAge;
}

/// Validates a field based on its config
String? validateField(
  FormFieldConfig f,
  String? textValue,
  DateTime? dateValue,
  String? dropdownValue,
  String? radioValue,
) {
  if (!f.required &&
      (textValue?.trim().isEmpty ?? true) &&
      dateValue == null &&
      dropdownValue == null &&
      radioValue == null) {
    return null; // Optional field, empty is OK
  }
  if (f.required &&
      (textValue?.trim().isEmpty ?? true) &&
      dateValue == null &&
      dropdownValue == null &&
      radioValue == null) {
    return '${f.label} is required.';
  }

  switch (f.type) {
    case FormFieldType.phone:
      if (!validatePhone(textValue)) {
        return f.validationMessage ??
            'Invalid phone number. Use format: 09XXXXXXXXX';
      }
      break;
    case FormFieldType.email:
      if (!validateEmail(textValue)) {
        return f.validationMessage ?? 'Invalid email address.';
      }
      break;
    case FormFieldType.number:
      if (!validateNumber(textValue)) {
        return f.validationMessage ?? 'Must be a valid number.';
      }
      break;
    case FormFieldType.date:
      if (f.minAge != null && dateValue != null) {
        if (!validateMinAge(dateValue, f.minAge!)) {
          return f.validationMessage ??
              'Must be at least ${f.minAge} years old.';
        }
      }
      break;
    default:
      // For text, textarea, dropdown, radio - just check required
      break;
  }

  // Custom regex pattern validation
  if (f.validationPattern != null &&
      textValue != null &&
      textValue.trim().isNotEmpty) {
    if (!RegExp(f.validationPattern!).hasMatch(textValue.trim())) {
      return f.validationMessage ?? 'Invalid format.';
    }
  }

  return null;
}
