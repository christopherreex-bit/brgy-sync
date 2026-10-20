import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/citizen_registry_service.dart';
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
                      'legalName': 'Full legal name',
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
                                (data[entry.key] ?? 'Not recorded').toString(),
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
    String field = 'legalName';
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
                            'legalName': 'Full legal name',
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
