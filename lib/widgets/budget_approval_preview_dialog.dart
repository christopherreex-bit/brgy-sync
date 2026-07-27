import 'package:flutter/material.dart';

import '../services/case_status_service.dart';
import '../utils/constants.dart';
import 'status_badge.dart';

Future<bool> showBudgetApprovalPreviewDialog(
  BuildContext context, {
  required String caseId,
}) async {
  final previewFuture = CaseStatusService().getBudgetApprovalPreview(
    caseId: caseId,
  );

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => FutureBuilder<BudgetApprovalPreview>(
          future: previewFuture,
          builder: (context, snapshot) {
            final preview = snapshot.data;
            return AlertDialog(
              title: const Text('Review Budget Before Approval'),
              content: SizedBox(
                width: 520,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : snapshot.hasError
                    ? _BudgetError(message: snapshot.error.toString())
                    : _BudgetPreviewContent(preview: preview!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: preview != null && preview.hasSufficientBalance
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  style: FilledButton.styleFrom(backgroundColor: kNavy),
                  child: const Text('Confirm Budget Review'),
                ),
              ],
            );
          },
        ),
      ) ??
      false;
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
    RegExp(r'(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  return '${negative ? '-' : ''}₱$grouped.${digits.last}';
}
