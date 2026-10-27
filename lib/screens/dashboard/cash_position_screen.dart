import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/cash_position_service.dart';
import '../../utils/constants.dart';

class CashPositionScreen extends StatefulWidget {
  const CashPositionScreen({super.key});

  @override
  State<CashPositionScreen> createState() => _CashPositionScreenState();
}

class _CashPositionScreenState extends State<CashPositionScreen> {
  final _service = CashPositionService();
  final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _reconcile();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _reconcile();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _reconcile() async {
    try {
      await _service.reconcileMaturedTransfers();
    } catch (_) {
      // The stream displays permission or connectivity errors to the user.
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AuthService>().currentUserModel;
    if (actor == null ||
        (!actor.isOfficer && !actor.isCaptain && !actor.isTreasurer)) {
      return const Center(child: Text('Cash position access is restricted.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _service.watchPosition(),
      builder: (context, positionSnapshot) {
        if (positionSnapshot.hasError) {
          return Center(
            child: Text(
              'Could not load cash position: ${positionSnapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        final data = positionSnapshot.data?.data();
        final initialized = data?['initialized'] == true;
        final bank = (data?['cashInBank'] as num?)?.toDouble() ?? 0;
        final hand = (data?['cashOnHand'] as num?)?.toDouble() ?? 0;
        final transit = (data?['cashInTransit'] as num?)?.toDouble() ?? 0;

        return SingleChildScrollView(
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
                          'Cash Position',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: kNavy,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Physical liquidity is tracked separately from budget availability.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (actor.isCaptain || actor.isTreasurer)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (initialized)
                          OutlinedButton.icon(
                            onPressed: () => _showBankReceiptDialog(actor),
                            icon: const Icon(Icons.add_card),
                            label: const Text('Record funds received'),
                          ),
                        FilledButton.icon(
                          onPressed: initialized
                              ? () => _showTransferDialog(actor)
                              : () => _showInitializeDialog(actor),
                          icon: Icon(
                            initialized
                                ? Icons.account_balance
                                : Icons.playlist_add_check,
                          ),
                          label: Text(
                            initialized
                                ? 'Withdraw to cash on hand'
                                : 'Initialize cash position',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Budget remaining shows spending authority. Cash on hand shows money physically available for release. A bank withdrawal stays in transit for 24 hours before becoming cash on hand.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (!initialized)
                _emptyState(actor.isCaptain || actor.isTreasurer)
              else ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _CashCard(
                        label: 'Cash in Bank',
                        amount: _money.format(bank),
                        icon: Icons.account_balance,
                        color: kNavy,
                      ),
                      _CashCard(
                        label: 'Cash in Transit',
                        amount: _money.format(transit),
                        icon: Icons.local_shipping_outlined,
                        color: Colors.orange,
                      ),
                      _CashCard(
                        label: 'Cash on Hand',
                        amount: _money.format(hand),
                        icon: Icons.payments_outlined,
                        color: Colors.green,
                      ),
                      _CashCard(
                        label: 'Total Liquid Cash',
                        amount: _money.format(bank + transit + hand),
                        icon: Icons.savings_outlined,
                        color: Colors.blue,
                      ),
                    ];
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: cards
                            .map(
                              (card) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: card,
                              ),
                            )
                            .toList(),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cards
                          .map(
                            (card) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: card,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Cash movement history',
                  style: TextStyle(
                    color: kNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _movementHistory(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState(bool canInitialize) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Cash balances have not been initialized.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            canInitialize
                ? 'Enter the verified opening bank and on-hand balances to begin the cash ledger.'
                : 'The Barangay Captain must enter the verified opening balances.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _movementHistory() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchMovements(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Could not load cash movements: ${snapshot.error}',
            style: const TextStyle(color: Colors.red),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Text('No cash movements recorded yet.');
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: snapshot.data!.docs.map((document) {
              final movement = document.data();
              final type = (movement['type'] ?? '').toString();
              final status = (movement['status'] ?? 'completed').toString();
              final amount = type == 'opening_balance'
                  ? ((movement['bankAmount'] as num?)?.toDouble() ?? 0) +
                        ((movement['onHandAmount'] as num?)?.toDouble() ?? 0)
                  : (movement['amount'] as num?)?.toDouble() ?? 0;
              final requestedAt = movement['requestedAt'];
              final effectiveAt = movement['effectiveAt'];
              final reference = (movement['referenceNumber'] ?? '').toString();
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _movementColor(type).withValues(alpha: .12),
                  child: Icon(_movementIcon(type), color: _movementColor(type)),
                ),
                title: Text(_movementLabel(type, status)),
                subtitle: Text(
                  [
                    if ((movement['reason'] ?? '').toString().isNotEmpty)
                      movement['reason'].toString(),
                    if ((movement['source'] ?? '').toString().isNotEmpty)
                      'Source: ${movement['source']}',
                    if (reference.isNotEmpty)
                      type == 'bank_receipt'
                          ? 'Reference: $reference'
                          : 'Case $reference',
                    if (requestedAt is Timestamp)
                      'Recorded ${DateFormat('MMM d, yyyy h:mm a').format(requestedAt.toDate())}',
                    if (status == 'pending' && effectiveAt is Timestamp)
                      'Expected ${DateFormat('MMM d, yyyy h:mm a').format(effectiveAt.toDate())}',
                  ].join(' · '),
                ),
                trailing: Text(
                  _money.format(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: type == 'case_disbursement'
                        ? Colors.red
                        : _movementColor(type),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  IconData _movementIcon(String type) => switch (type) {
    'bank_receipt' => Icons.add_card,
    'bank_to_hand' => Icons.sync_alt,
    'case_disbursement' => Icons.money_off,
    _ => Icons.account_balance_wallet_outlined,
  };

  Color _movementColor(String type) => switch (type) {
    'bank_receipt' => Colors.green,
    'bank_to_hand' => Colors.orange,
    'case_disbursement' => Colors.red,
    _ => Colors.blue,
  };

  String _movementLabel(String type, String status) => switch (type) {
    'bank_receipt' => 'Funds received in bank',
    'bank_to_hand' =>
      status == 'pending'
          ? 'Bank withdrawal in transit'
          : 'Bank withdrawal received',
    'case_disbursement' => 'Cash assistance released',
    _ => 'Opening cash position',
  };

  Future<void> _showBankReceiptDialog(UserModel actor) async {
    final amount = TextEditingController();
    final source = TextEditingController();
    final reference = TextEditingController();
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record funds received'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Incoming funds are recorded in cash in bank. This increases actual cash but does not create or increase a program allocation.',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount received',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(
                    labelText: 'Funding source',
                    hintText: 'Example: City Government transfer',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Deposit or reference number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Purpose or accounting note',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Record receipt'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runAction(
        () => _service.recordBankReceipt(
          amount: double.tryParse(amount.text.replaceAll(',', '')) ?? -1,
          source: source.text,
          referenceNumber: reference.text,
          reason: reason.text,
          actor: actor,
        ),
        'Incoming funds recorded in cash in bank.',
      );
    }
    amount.dispose();
    source.dispose();
    reference.dispose();
    reason.dispose();
  }

  Future<void> _showInitializeDialog(UserModel actor) async {
    CashBudgetPosition budget;
    try {
      budget = await _service.getCurrentBudgetPosition();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load current budget totals: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final bank = TextEditingController();
    final hand = TextEditingController();
    final reason = TextEditingController();
    var acknowledged = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bankAmount = _parseAmount(bank.text);
          final handAmount = _parseAmount(hand.text);
          final totalCash = bankAmount + handAmount;
          final difference = totalCash - budget.undisbursed;
          final onHandCoverageDifference = handAmount - budget.reserved;
          final exceedsBudget = difference > 0;
          final hasOnHandShortfall = onHandCoverageDifference < 0;
          final valid =
              bankAmount >= 0 &&
              handAmount >= 0 &&
              reason.text.trim().isNotEmpty &&
              (!exceedsBudget || acknowledged);
          return AlertDialog(
            title: const Text('Initialize cash position'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Use verified treasury or bank records. Cash is compared with the current program budget but is not automatically treated as budget allocation.',
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fiscal year budget · FY ${budget.fiscalYear} (Q1–Q4)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kNavy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _dialogAmountRow('Allocated', budget.allocated),
                          _dialogAmountRow('Utilized', budget.utilized),
                          _dialogAmountRow(
                            'Reserved but not released (all quarters)',
                            budget.reserved,
                          ),
                          _dialogAmountRow(
                            'Available for new approvals',
                            budget.available,
                          ),
                          _dialogAmountRow(
                            'Total undisbursed budget',
                            budget.undisbursed,
                            emphasize: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: bank,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Opening cash in bank',
                        prefixText: '₱ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hand,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Opening cash on hand',
                        prefixText: '₱ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _dialogAmountRow('Entered total liquid cash', totalCash),
                    _dialogAmountRow(
                      'Liquid cash vs. undisbursed budget',
                      difference,
                      emphasize: true,
                    ),
                    _dialogAmountRow(
                      'Cash on hand vs. reserved payouts',
                      onHandCoverageDifference,
                      emphasize: true,
                    ),
                    if (hasOnHandShortfall) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Cash on hand is ${_money.format(-onHandCoverageDifference)} below the amount reserved for approved but unreleased cases. This is allowed, but bank funds must arrive before all of those cases can be released.',
                          style: TextStyle(color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                    if (exceedsBudget) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          border: Border.all(color: Colors.orange.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Total liquid cash exceeds the full fiscal year undisbursed program budget by ${_money.format(difference)}. This can be valid when the excess belongs to operations, other funds, collections, or timing differences. Explain and confirm it below.',
                          style: TextStyle(color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: reason,
                      maxLines: 3,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: exceedsBudget
                            ? 'Required reconciliation explanation'
                            : 'Source or reconciliation reason',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (exceedsBudget)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: acknowledged,
                        onChanged: (value) =>
                            setDialogState(() => acknowledged = value == true),
                        title: const Text(
                          'I confirm that the excess cash has been reviewed and the explanation is accurate.',
                          style: TextStyle(fontSize: 13),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Initialize'),
              ),
            ],
          );
        },
      ),
    );
    if (result == true) {
      await _runAction(
        () => _service.initialize(
          cashInBank: double.tryParse(bank.text.replaceAll(',', '')) ?? -1,
          cashOnHand: double.tryParse(hand.text.replaceAll(',', '')) ?? -1,
          reason: reason.text,
          actor: actor,
          excessAcknowledged: acknowledged,
        ),
        'Cash position initialized.',
      );
    }
    bank.dispose();
    hand.dispose();
    reason.dispose();
  }

  double _parseAmount(String value) {
    if (value.trim().isEmpty) return 0;
    return double.tryParse(value.replaceAll(',', '')) ?? -1;
  }

  Widget _dialogAmountRow(
    String label,
    double amount, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(
            _money.format(amount),
            style: TextStyle(
              fontSize: 12,
              fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
              color: amount < 0 ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTransferDialog(UserModel actor) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Transfer bank funds to cash on hand'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'The amount leaves cash in bank immediately, remains in transit, and arrives in cash on hand after 24 hours.',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for withdrawal',
                  border: OutlineInputBorder(),
                ),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Request transfer'),
          ),
        ],
      ),
    );
    if (result == true) {
      await _runAction(
        () => _service.requestBankToHandTransfer(
          amount: double.tryParse(amount.text.replaceAll(',', '')) ?? -1,
          reason: reason.text,
          actor: actor,
        ),
        'Transfer requested. Funds will arrive in 24 hours.',
      );
    }
    amount.dispose();
    reason.dispose();
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
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
}

class _CashCard extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  const _CashCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        border: Border.all(color: color.withValues(alpha: .2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 3),
                Text(
                  amount,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
