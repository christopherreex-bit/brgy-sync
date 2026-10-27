import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/incentive_distribution_service.dart';
import '../../utils/constants.dart';
import '../../widgets/status_badge.dart';

class DistributionsScreen extends StatefulWidget {
  const DistributionsScreen({super.key});

  @override
  State<DistributionsScreen> createState() => _DistributionsScreenState();
}

class _DistributionsScreenState extends State<DistributionsScreen> {
  final _service = IncentiveDistributionService();
  final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  String _activeTab = 'all';

  static const _tabs = [
    {'key': 'all', 'label': 'All Incentives'},
    {'key': 'senior_birthday', 'label': 'Senior Citizen'},
    {'key': 'pwd_birthday', 'label': 'PWD'},
  ];

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AuthService>().currentUserModel;
    if (actor == null || (!actor.isOfficer && !actor.isCaptain)) {
      return const Center(
        child: Text('Distribution program access is restricted.'),
      );
    }
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
                      'Distribution Programs',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Release incentives to completed Senior Citizen and PWD registrations.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (actor.isCaptain)
                FilledButton.icon(
                  onPressed: () => _showReleaseDialog(actor),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Release incentive'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'A payout requires a completed beneficiary registration, an available current-quarter allocation, and enough cash on hand. Education Incentives continue through the normal case workflow.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tabs.map((tab) {
              return ChoiceChip(
                selected: _activeTab == tab['key'],
                label: Text(tab['label']!),
                onSelected: (_) => setState(() => _activeTab = tab['key']!),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Expanded(child: _distributionList()),
        ],
      ),
    );
  }

  Widget _distributionList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchDistributions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Could not load incentive records. Check your connection and Firestore rules.',
              style: TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final records = snapshot.data!.docs.where((document) {
          return _activeTab == 'all' ||
              document.data()['programType'] == _activeTab;
        }).toList();
        if (records.isEmpty) {
          return const Center(
            child: Text('No incentive releases recorded yet.'),
          );
        }
        return ListView.separated(
          itemCount: records.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = records[index].data();
            final releasedAt = data['releasedAt'];
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.card_giftcard)),
                title: Text(
                  (data['beneficiaryName'] ?? 'Unnamed beneficiary').toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  [
                    data['programName'] ?? '',
                    if ((data['referenceNumber'] ?? '').toString().isNotEmpty)
                      'Registration ${data['referenceNumber']}',
                    if (releasedAt is Timestamp)
                      DateFormat(
                        'MMM d, yyyy h:mm a',
                      ).format(releasedAt.toDate()),
                    if ((data['reason'] ?? '').toString().isNotEmpty)
                      data['reason'],
                  ].where((value) => value.toString().isNotEmpty).join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _money.format((data['amount'] as num?)?.toDouble() ?? 0),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    StatusBadge(
                      status: (data['status'] ?? 'released').toString(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showReleaseDialog(UserModel actor) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await FirebaseFirestore.instance
          .collection('cases')
          .where('serviceCategory', isEqualTo: 'beneficiary')
          .get();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load completed registrations. Check your connection and deploy the latest Firestore rules.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final registrations =
        snapshot.docs.where((document) {
          final data = document.data();
          return data['status'] == 'released' &&
              (data['serviceSubType'] == 'Senior Citizen Birthday Program' ||
                  data['serviceSubType'] == 'PWD Birthday Program');
        }).toList()..sort(
          (a, b) =>
              _beneficiaryName(a.data()).compareTo(_beneficiaryName(b.data())),
        );
    if (!mounted) return;
    if (registrations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No completed Senior Citizen or PWD registrations are eligible.',
          ),
        ),
      );
      return;
    }

    String? selectedId;
    IncentiveReleasePreview? preview;
    String? previewError;
    bool loadingPreview = false;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Release beneficiary incentive'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Completed beneficiary registration',
                    border: OutlineInputBorder(),
                  ),
                  items: registrations.map((document) {
                    final data = document.data();
                    return DropdownMenuItem(
                      value: document.id,
                      child: Text(
                        '${_beneficiaryName(data)} · ${data['serviceSubType']} · ${data['referenceNumber'] ?? document.id}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    setDialogState(() {
                      selectedId = value;
                      preview = null;
                      previewError = null;
                      loadingPreview = value != null;
                    });
                    if (value == null) return;
                    final registration = registrations.firstWhere(
                      (document) => document.id == value,
                    );
                    final programType =
                        registration.data()['serviceSubType'] ==
                            'Senior Citizen Birthday Program'
                        ? 'senior_birthday'
                        : 'pwd_birthday';
                    try {
                      final result = await _service.getReleasePreview(
                        programType: programType,
                      );
                      if (dialogContext.mounted) {
                        setDialogState(() {
                          preview = result;
                          loadingPreview = false;
                        });
                      }
                    } catch (error) {
                      if (dialogContext.mounted) {
                        setDialogState(() {
                          previewError = error.toString().replaceFirst(
                            'Bad state: ',
                            '',
                          );
                          loadingPreview = false;
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, color: kNavy, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Fixed incentive amount: ₱1,000.00\nThe amount is set by the program and cannot be changed.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                if (loadingPreview) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (previewError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    previewError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  _releaseBreakdown(preview!),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason or distribution authority',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  selectedId == null ||
                      preview?.canRelease != true ||
                      reason.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm release'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedId != null) {
      final registration = registrations.firstWhere(
        (document) => document.id == selectedId,
      );
      try {
        await _service.release(
          registrationCaseId: selectedId!,
          programType:
              registration.data()['serviceSubType'] ==
                  'Senior Citizen Birthday Program'
              ? 'senior_birthday'
              : 'pwd_birthday',
          reason: reason.text,
          actor: actor,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incentive released and recorded.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$error'), backgroundColor: Colors.red),
          );
        }
      }
    }
    reason.dispose();
  }

  Widget _releaseBreakdown(IncentiveReleasePreview preview) {
    Widget line(String label, double value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _money.format(value),
            style: TextStyle(fontWeight: strong ? FontWeight.bold : null),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: preview.canRelease ? Colors.green.shade50 : Colors.red.shade50,
        border: Border.all(
          color: preview.canRelease
              ? Colors.green.shade200
              : Colors.red.shade200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${preview.programName} · FY ${preview.fiscalYear} Q${preview.quarter}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: kNavy),
          ),
          const SizedBox(height: 6),
          line('Total allocation', preview.allocated),
          line('Already released', -preview.utilized),
          if (preview.reserved > 0)
            line('Reserved / on hold', -preview.reserved),
          line('Available program budget', preview.available),
          line('Less: fixed incentive', -preview.amount),
          const Divider(),
          line(
            'Remaining budget after release',
            preview.remainingAfterRelease,
            strong: true,
          ),
          const SizedBox(height: 6),
          line('Cash on hand', preview.cashOnHand),
          line(
            'Cash on hand after release',
            preview.cashOnHandAfterRelease,
            strong: true,
          ),
          if (!preview.hasEnoughBudget)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Release blocked: the available program budget is below ₱1,000.00.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (!preview.hasEnoughCash)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Release blocked: cash on hand is below ₱1,000.00.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _beneficiaryName(Map<String, dynamic> data) =>
      (data['fullName'] ?? data['residentName'] ?? 'Unnamed').toString();
}
