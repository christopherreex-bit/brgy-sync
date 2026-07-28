import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'status_badge.dart';

class BudgetProgramCard extends StatelessWidget {
  final String programName;
  final String status;
  final double allocated;
  final double utilized;
  final double reserved;

  const BudgetProgramCard({
    super.key,
    required this.programName,
    required this.status,
    required this.allocated,
    required this.utilized,
    this.reserved = 0,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = allocated - utilized - reserved;
    final progress = allocated > 0
        ? ((utilized + reserved) / allocated).clamp(0.0, 1.0)
        : 0.0;

    Color barColor;
    if (status == budgetCritical) {
      barColor = Colors.red;
    } else if (status == budgetLow) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  programName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: kNavy,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusBadge(status: status),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          if (reserved > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '₱${reserved.toStringAsFixed(0)} reserved for release',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₱${utilized.toStringAsFixed(0)} of ₱${allocated.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                '₱${remaining.toStringAsFixed(0)} available',
                style: TextStyle(
                  fontSize: 12,
                  color: barColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
