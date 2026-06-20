import 'package:flutter/material.dart';
import '../utils/constants.dart';

class SlaBar extends StatelessWidget {
  final String slaStatus;
  final String timeRemaining;

  const SlaBar({
    super.key,
    required this.slaStatus,
    required this.timeRemaining,
  });

  @override
  Widget build(BuildContext context) {
    Color barColor;
    switch (slaStatus) {
      case slaOnTime:
        barColor = Colors.green;
        break;
      case slaNearDeadline:
        barColor = Colors.orange;
        break;
      case slaOverdue:
        barColor = Colors.red;
        break;
      default:
        barColor = Colors.grey;
    }

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: slaStatus == slaOverdue ? 1.0 : 0.6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(timeRemaining,
            style: TextStyle(fontSize: 11, color: barColor, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
