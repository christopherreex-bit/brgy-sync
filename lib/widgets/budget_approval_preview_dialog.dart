import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/case_status_service.dart';
import '../utils/constants.dart';
import 'status_badge.dart';

class BudgetApprovalConfirmation {
  final double? assistanceAmount;

  const BudgetApprovalConfirmation({this.assistanceAmount});
}

Future<BudgetApprovalConfirmation?> showBudgetApprovalPreviewDialog(
  BuildContext context, {
  required String caseId,
}) async {
  final caseSnapshot = await FirebaseFirestore.instance
      .collection('cases')
      .doc(caseId)
      .get();
  if (!caseSnapshot.exists) throw StateError('Case not found.');
  final category = (caseSnapshot.data()?['serviceCategory'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final existingAmount = (caseSnapshot.data()?['assistanceAmount'] as num?)
      ?.toDouble();
  if (!context.mounted) return null;

  if (category != 'bass' && category != 'education') {
    return const BudgetApprovalConfirmation();
  }

  return showDialog<BudgetApprovalConfirmation>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BudgetApprovalDialog(
      caseId: caseId,
      amountProgramCategory: category == 'bass' || category == 'education'
          ? category
          : null,
      initialAmount: category == 'bass' ? existingAmount : null,
    ),
  );
}

class _BudgetApprovalDialog extends StatefulWidget {
  final String caseId;
  final String? amountProgramCategory;
  final double? initialAmount;

  const _BudgetApprovalDialog({
    required this.caseId,
    required this.amountProgramCategory,
    required this.initialAmount,
  });

  @override
  State<_BudgetApprovalDialog> createState() => _BudgetApprovalDialogState();
}

class _BudgetApprovalDialogState extends State<_BudgetApprovalDialog> {
  final _amountController = TextEditingController();
  Future<BudgetApprovalPreview>? _previewFuture;
  double? _finalAmount;
  String? _amountError;

  bool get _requiresFinalAmount => widget.amountProgramCategory != null;
  bool get _isEducation => widget.amountProgramCategory == 'education';
  bool get _isBass => widget.amountProgramCategory == 'bass';

  @override
  void initState() {
    super.initState();
    final initialAmount = widget.initialAmount;
    if (_requiresFinalAmount &&
        initialAmount != null &&
        initialAmount.isFinite &&
        initialAmount > 0) {
      _amountController.text = initialAmount.toStringAsFixed(2);
      _finalAmount = initialAmount;
      _previewFuture = CaseStatusService().getBudgetApprovalPreview(
        caseId: widget.caseId,
        assistanceAmountOverride: initialAmount,
      );
    } else if (!_requiresFinalAmount) {
      _previewFuture = CaseStatusService().getBudgetApprovalPreview(
        caseId: widget.caseId,
      );
    }
  }

  void _updateFinalAmount(String value) {
    final amount = double.tryParse(value.trim());
    String? error;
    if (value.trim().isEmpty) {
      error = 'Enter the final assistance amount.';
    } else if (amount == null) {
      error = 'Enter a valid amount.';
    } else if (!amount.isFinite) {
      error = 'Enter a valid amount.';
    } else if (_isEducation && (amount < 500 || amount > 1000)) {
      error = 'Amount must be from ₱500 to ₱1,000.';
    } else if (amount <= 0) {
      error = 'Amount must be greater than zero.';
    }
    setState(() {
      _amountError = error;
      _finalAmount = error == null ? amount : null;
      _previewFuture = error == null
          ? CaseStatusService().getBudgetApprovalPreview(
              caseId: widget.caseId,
              assistanceAmountOverride: amount,
            )
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BudgetApprovalPreview>(
      future: _previewFuture,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        return AlertDialog(
          title: const Text('Review Budget Before Approval'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_requiresFinalAmount) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isEducation
                            ? 'Set the final Education Incentive amount before '
                                  'approval.'
                            : _isBass
                            ? 'Review or edit the requested BASS assistance '
                                  'amount before approval.'
                            : 'Set the final birthday-program assistance '
                                  'amount before approval.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _isEducation
                            ? 'Final assistance amount (₱500–₱1,000)'
                            : 'Final assistance amount',
                        prefixText: '₱ ',
                        border: const OutlineInputBorder(),
                        errorText: _amountError,
                      ),
                      onChanged: _updateFinalAmount,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_previewFuture == null)
                    _InfoPanel(
                      icon: Icons.edit_outlined,
                      message: _isEducation
                          ? 'Enter an amount from ₱500 to ₱1,000 to calculate '
                                'the remaining budget.'
                          : 'Enter the final assistance amount to calculate '
                                'the remaining budget.',
                    )
                  else if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError)
                    _BudgetError(message: snapshot.error.toString())
                  else
                    _BudgetPreviewContent(preview: preview!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  preview != null &&
                      preview.hasSufficientBalance &&
                      (!_requiresFinalAmount || _finalAmount != null)
                  ? () => Navigator.pop(
                      context,
                      BudgetApprovalConfirmation(
                        assistanceAmount: _finalAmount,
                      ),
                    )
                  : null,
              style: FilledButton.styleFrom(backgroundColor: kNavy),
              child: const Text('Confirm Budget Review'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}

class _BudgetPreviewContent extends StatelessWidget {
  final BudgetApprovalPreview preview;

  const _BudgetPreviewContent({required this.preview});

  @override
  Widget build(BuildContext context) {
    if (!preview.hasBudgetImpact) {
      return const _InfoPanel(
        icon: Icons.info_outline,
        message:
            'This case has no assistance amount linked to a quarterly budget. '
            'No budget deduction will apply.',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                preview.programName!,
                style: const TextStyle(
                  color: kNavy,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (preview.currentStatus.isNotEmpty)
              StatusBadge(status: preview.currentStatus),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'FY ${preview.fiscalYear} · Q${preview.quarter}',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        _AmountRow(label: 'Allocated budget', amount: preview.allocated),
        _AmountRow(label: 'Already utilized', amount: preview.utilized),
        _AmountRow(
          label: 'Current remaining balance',
          amount: preview.currentRemaining,
        ),
        const Divider(height: 24),
        _AmountRow(
          label: 'This case assistance amount',
          amount: preview.assistanceAmount,
          emphasized: true,
        ),
        _AmountRow(
          label: 'Projected remaining balance',
          amount: preview.projectedRemaining,
          emphasized: true,
          color: preview.hasSufficientBalance ? Colors.green : Colors.red,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_currency(preview.currentRemaining)} − '
            '${_currency(preview.assistanceAmount)} = '
            '${_currency(preview.projectedRemaining)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kNavy,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _InfoPanel(
          icon: preview.hasSufficientBalance
              ? Icons.check_circle_outline
              : Icons.error_outline,
          message: preview.hasSufficientBalance
              ? 'Confirming acknowledges this budget impact. The deduction is posted when the case reaches Released.'
              : 'This budget does not have enough remaining balance for the case amount.',
          color: preview.hasSufficientBalance ? Colors.blue : Colors.red,
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool emphasized;
  final Color? color;

  const _AmountRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _currency(amount),
            style: TextStyle(
              color: color,
              fontWeight: emphasized ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _InfoPanel({
    required this.icon,
    required this.message,
    this.color = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _BudgetError extends StatelessWidget {
  final String message;

  const _BudgetError({required this.message});

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      icon: Icons.error_outline,
      color: Colors.red,
      message: 'Could not load the applicable budget: $message',
    );
  }
}

String _currency(double amount) {
  final negative = amount < 0;
  final digits = amount.abs().toStringAsFixed(2).split('.');
  final whole = digits.first;
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  return '${negative ? '-' : ''}₱$grouped.${digits.last}';
}
