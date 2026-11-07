import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/citizen_registry_service.dart';
import '../../services/indigency_certificate_service.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';

class CitizenRecordScreen extends StatelessWidget {
  const CitizenRecordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUserModel;
    if (user == null) return const Center(child: Text('Session unavailable.'));
    final service = CitizenRegistryService();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchRecordByMobile(user.mobile),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No Citizen Registry record matches your account mobile number. '
                'Please visit or contact the barangay to have the official record checked.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final record = snapshot.data!.docs.first;
        final data = record.data();
        final parsedName = UserModel.splitLegacyName(
          (data['legalName'] ?? '').toString(),
        );
        final displayData = <String, dynamic>{
          ...data,
          'firstName': data['firstName'] ?? parsedName.firstName,
          'middleName': data['middleName'] ?? parsedName.middleName,
          'lastName': data['lastName'] ?? parsedName.lastName,
        };
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'My Citizen Record',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: kNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This is your barangay registry record. Submit a correction request if information is missing or incorrect.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(label: Text(_status(data['verificationStatus']))),
                    const SizedBox(height: 10),
                    ...<String, String>{
                      'firstName': 'First name',
                      'middleName': 'Middle initial',
                      'lastName': 'Last name',
                      'dateOfBirth': 'Date of birth',
                      'sex': 'Sex',
                      'civilStatus': 'Civil status',
                      'nationality': 'Nationality',
                      'permanentAddress': 'Permanent address',
                      'temporaryAddress': 'Temporary address',
                      'residencySince': 'Resident since',
                      'mobile': 'Mobile',
                      'email': 'Email',
                      'householdId': 'Household ID',
                      'employmentStatus': 'Employment status',
                      'occupation': 'Occupation',
                      'incomeBracket': 'Income bracket',
                      'voterStatus': 'Voter status',
                      'precinctNumber': 'Precinct number',
                      'emergencyContactName': 'Emergency contact',
                      'emergencyContactMobile': 'Emergency contact mobile',
                    }.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 190,
                              child: Text(
                                entry.value,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                (displayData[entry.key] ?? 'Not recorded')
                                    .toString(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if ((data['classifications'] as List?)?.isNotEmpty == true)
                      Text(
                        'Classifications: ${(data['classifications'] as List).join(', ')}',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ResidentVerifiedDocuments(registryId: record.id),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () =>
                    _requestCorrection(context, service, user, record.id),
                icon: const Icon(Icons.edit_note),
                label: const Text('Request a correction'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _requestCorrection(
    BuildContext context,
    CitizenRegistryService service,
    user,
    String registryId,
  ) async {
    String field = 'firstName';
    final value = TextEditingController();
    final reason = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Request a registry correction'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: field,
                  decoration: const InputDecoration(
                    labelText: 'Information to correct',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const {
                            'firstName': 'First name',
                            'middleName': 'Middle initial',
                            'lastName': 'Last name',
                            'dateOfBirth': 'Date of birth',
                            'sex': 'Sex',
                            'civilStatus': 'Civil status',
                            'nationality': 'Nationality',
                            'permanentAddress': 'Permanent address',
                            'temporaryAddress': 'Temporary address',
                            'residencySince': 'Resident since',
                            'mobile': 'Mobile',
                            'email': 'Email',
                            'householdId': 'Household ID',
                            'familyComposition': 'Family composition',
                            'dependencies': 'Dependencies',
                            'employmentStatus': 'Employment status',
                            'occupation': 'Occupation',
                            'incomeBracket': 'Income bracket',
                            'classificationsText': 'Classifications',
                            'voterStatus': 'Voter status',
                            'precinctNumber': 'Precinct number',
                            'emergencyContactName': 'Emergency contact name',
                            'emergencyContactMobile':
                                'Emergency contact mobile',
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => field = v ?? field),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: value,
                  decoration: const InputDecoration(
                    labelText: 'Correct information *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason or supporting explanation *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                value.text.trim().isNotEmpty && reason.text.trim().isNotEmpty,
              ),
              child: const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true) {
      final correctionField = field == 'classificationsText'
          ? 'classifications'
          : field;
      await service.submitCorrection(
        registryId: registryId,
        resident: user,
        field: correctionField,
        proposedValue: value.text,
        reason: reason.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Correction request submitted for review.'),
          ),
        );
      }
    }
    value.dispose();
    reason.dispose();
  }

  String _status(dynamic value) => switch (value) {
    'verified' => 'Verified by barangay',
    'pending_verification' => 'Pending verification',
    _ => 'Unverified record',
  };
}

class _ResidentVerifiedDocuments extends StatelessWidget {
  const _ResidentVerifiedDocuments({required this.registryId});

  final String registryId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Issued and verified documents',
              style: TextStyle(
                color: kNavy,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Valid documents shown here may be reused automatically in future service requests.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('citizenRegistry')
                  .doc(registryId)
                  .collection('verifiedDocuments')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final now = DateTime.now();
                final documents = snapshot.data!.docs.where((document) {
                  final data = document.data();
                  if (data['verificationStatus'] != 'verified') return false;
                  final validUntil = data['validUntil'];
                  return validUntil is! Timestamp ||
                      !validUntil.toDate().isBefore(now);
                }).toList();
                if (documents.isEmpty) {
                  return const Text('No valid issued documents on file.');
                }
                return Column(
                  children: documents.map((document) {
                    final data = document.data();
                    final expiry = data['validUntil'];
                    final expiryText = expiry is Timestamp
                        ? 'Valid until ${_shortDate(expiry.toDate())}'
                        : 'No expiry recorded';
                    final canOpen =
                        (data['databasePath'] ?? '').toString().isNotEmpty &&
                        (data['encryptionKey'] ?? '').toString().isNotEmpty;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.verified_outlined,
                        color: Colors.green,
                      ),
                      title: Text(
                        (data['name'] ?? 'Verified document').toString(),
                      ),
                      subtitle: Text(
                        '${data['certificateNumber'] ?? data['fileName'] ?? ''}'
                        '${(data['certificateNumber'] ?? data['fileName'] ?? '').toString().isEmpty ? '' : ' · '}$expiryText',
                      ),
                      trailing: canOpen
                          ? OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  await IndigencyCertificateService()
                                      .previewStored(data);
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not open document: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Open'),
                            )
                          : null,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _shortDate(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';
}
