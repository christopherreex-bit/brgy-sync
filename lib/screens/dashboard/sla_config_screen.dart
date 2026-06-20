import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class SlaConfigScreen extends StatefulWidget {
  const SlaConfigScreen({super.key});

  @override
  State<SlaConfigScreen> createState() => _SlaConfigScreenState();
}

class _SlaConfigScreenState extends State<SlaConfigScreen> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isCaptain = auth.currentUserModel?.isCaptain ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SLA Configuration',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kNavy)),
          const SizedBox(height: 4),
          const Text('Configure SLA deadlines per service category.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
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
            stream: FirebaseFirestore.instance.collection('slaConfig').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                // Show defaults if not seeded
                return _buildDefaultConfig(isCaptain);
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildConfigRow(doc.id, data, isCaptain);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultConfig(bool isCaptain) {
    final defaults = [
      _SlaEntry('Document Certifications', 15, 'minutes'),
      _SlaEntry('BASS – Standard', 3, 'working_days'),
      _SlaEntry('BASS – Medical', 5, 'working_days'),
      _SlaEntry('VAW / BCPC Reports', 1, 'working_days'),
    ];

    return Column(
      children: defaults.map((e) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text('${e.value} ${e.unit.replaceAll('_', ' ')}'),
          trailing: isCaptain ? const Icon(Icons.edit, color: kNavy) : null,
          onTap: isCaptain ? () => _showEditDialog(e) : null,
        ),
      )).toList(),
    );
  }

  Widget _buildConfigRow(String docId, Map<String, dynamic> data, bool isCaptain) {
    final category = data['category'] ?? '';
    final value = data['deadlineValue']?.toString() ?? '';
    final unit = (data['deadlineUnit'] ?? '').replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('$value $unit'),
        trailing: isCaptain ? const Icon(Icons.edit, color: kNavy) : null,
        onTap: isCaptain ? () => _showEditDialog(_SlaEntry(category, int.tryParse(value) ?? 0, data['deadlineUnit'] ?? 'working_days')) : null,
      ),
    );
  }

  void _showEditDialog(_SlaEntry entry) {
    final valueCtrl = TextEditingController(text: entry.value.toString());
    String unit = entry.unit;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
              value: unit,
              decoration: const InputDecoration(
                labelText: 'Unit',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'minutes', child: Text('Minutes')),
                DropdownMenuItem(value: 'working_days', child: Text('Working Days')),
              ],
              onChanged: (v) => unit = v ?? unit,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => _saveSla(entry.name, int.tryParse(valueCtrl.text) ?? entry.value, unit),
            style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSla(String category, int value, String unit) async {
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      // Find or create
      final snap = await db.collection('slaConfig').where('category', isEqualTo: category).get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({
          'deadlineValue': value,
          'deadlineUnit': unit,
          'lastUpdatedBy': context.read<AuthService>().currentUserModel?.uid ?? '',
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await db.collection('slaConfig').add({
          'category': category,
          'deadlineValue': value,
          'deadlineUnit': unit,
          'lastUpdatedBy': context.read<AuthService>().currentUserModel?.uid ?? '',
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SLA updated.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _SlaEntry {
  final String name;
  final int value;
  final String unit;
  _SlaEntry(this.name, this.value, this.unit);
}
