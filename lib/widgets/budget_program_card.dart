import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'status_badge.dart';

class BudgetProgramCard extends StatelessWidget {
  final String programName;
  final String status;
  final double allocated;
  final double utilized;

  const BudgetProgramCard({
    super.key,
    required this.programName,
    required this.status,
    required this.allocated,
    required this.utilized,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = allocated - utilized;
    final progress = allocated > 0 ? (utilized / allocated).clamp(0.0, 1.0) : 0.0;

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
                child: Text(programName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
              ),
              StatusBadge(status: status),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₱${utilized.toStringAsFixed(0)} of ₱${allocated.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text('₱${remaining.toStringAsFixed(0)} left',
                  style: TextStyle(fontSize: 12, color: barColor, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
