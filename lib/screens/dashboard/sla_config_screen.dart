import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import '../../utils/sla_calculator.dart' as sla;
import '../../models/service_category.dart';

const _slaLabels = {
  'documents': 'Document Certifications',
  'bass_standard': 'BASS – Standard',
  'bass_medical': 'BASS – Medical',
  'vaw': 'VAW / BCPC Reports',
  'community': 'Community Services',
  'beneficiary': 'Beneficiary Registration',
  'education': 'Education Incentive',
  'adhoc': 'Ad Hoc / Special Program',
};

class SlaConfigScreen extends StatefulWidget {
  const SlaConfigScreen({super.key});

  @override
  State<SlaConfigScreen> createState() => _SlaConfigScreenState();
}

class _SlaConfigScreenState extends State<SlaConfigScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isCaptain = auth.currentUserModel?.isCaptain ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SLA Configuration',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: kNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Configure SLA deadlines per service category.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),

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
                    "Mandated under the Citizens' Charter and Ease of Doing Business Act. Consult your legal officer before modifying.",
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('slaConfig')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];
              final config = sla.buildSlaConfig(
                docs.map((doc) => doc.data() as Map<String, dynamic>),
              );
              return Column(
                children: kSlaDefaults.keys.map((key) {
                  final rule = config[key]!;
                  return _buildConfigRow(
                    _SlaEntry(
                      key,
                      _slaLabels[key] ?? key,
                      rule['value'] as int,
                      rule['unit'] as String,
                    ),
                    isCaptain,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(_SlaEntry entry, bool isCaptain) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          entry.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text('${entry.value} ${entry.unit.replaceAll('_', ' ')}'),
        trailing: isCaptain ? const Icon(Icons.edit, color: kNavy) : null,
        onTap: isCaptain ? () => _showEditDialog(entry) : null,
      ),
    );
  }

  void _showEditDialog(_SlaEntry entry) {
    final valueCtrl = TextEditingController(text: entry.value.toString());
    String unit = entry.unit;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Edit SLA: ${entry.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Deadline Value',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: unit,
              decoration: const InputDecoration(
                labelText: 'Unit',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'minutes', child: Text('Minutes')),
                DropdownMenuItem(
                  value: 'working_days',
                  child: Text('Working Days'),
                ),
              ],
              onChanged: (v) => unit = v ?? unit,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _saveSla(
                entry.key,
                int.tryParse(valueCtrl.text) ?? entry.value,
                unit,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kNavy,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSla(String categoryKey, int value, String unit) async {
    if (value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SLA deadline must be greater than zero.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final updatedBy = context.read<AuthService>().currentUserModel?.uid ?? '';
      final snap = await db
          .collection('slaConfig')
          .where('category', isEqualTo: categoryKey)
          .get();

      final values = {
        'category': categoryKey,
        'deadlineValue': value,
        'deadlineUnit': unit,
        'lastUpdatedBy': updatedBy,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

      // Keep one predictable document per SLA key. Older seed runs may have
      // created duplicate random-ID documents, so update those too; otherwise
      // a stale duplicate can override the newly edited value in live screens.
      final canonicalRef = db.collection('slaConfig').doc(categoryKey);
      final batch = db.batch();
      batch.set(canonicalRef, values, SetOptions(merge: true));
      for (final document in snap.docs) {
        if (document.id != categoryKey) {
          batch.set(document.reference, values, SetOptions(merge: true));
        }
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SLA updated.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _SlaEntry {
  final String key;
  final String name;
  final int value;
  final String unit;
  _SlaEntry(this.key, this.name, this.value, this.unit);
}
