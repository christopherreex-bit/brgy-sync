import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/constants.dart';

class SlaBar extends StatelessWidget {
  final String slaStatus;
  final String timeRemaining;
  final DateTime submittedAt;
  final DateTime deadline;

  const SlaBar({
    super.key,
    required this.slaStatus,
    required this.timeRemaining,
    required this.submittedAt,
    required this.deadline,
  });

  @override
  Widget build(BuildContext context) {
    Color barColor;
    Color trackColor;
    switch (slaStatus) {
      case slaOnTime:
        barColor = const Color(0xFF16A34A);
        trackColor = const Color(0xFFDCFCE7);
        break;
      case slaNearDeadline:
        barColor = const Color(0xFFF59E0B);
        trackColor = const Color(0xFFFEF3C7);
        break;
      case slaOverdue:
        barColor = const Color(0xFFEF4444);
        trackColor = const Color(0xFFFEE2E2);
        break;
      default:
        barColor = Colors.grey.shade600;
        trackColor = Colors.grey.shade200;
    }

    final now = DateTime.now();
    final totalMilliseconds = math.max(
      1,
      deadline.difference(submittedAt).inMilliseconds,
    );
    final elapsedMilliseconds = math.max(
      0,
      now.difference(submittedAt).inMilliseconds,
    );
    final progress = (elapsedMilliseconds / totalMilliseconds).clamp(0.0, 1.0);

    return Tooltip(
      message: _timelineDescription(now),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: slaStatus == slaOverdue ? 1.0 : progress,
                backgroundColor: trackColor,
                valueColor: AlwaysStoppedAnimation(barColor),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeRemaining,
            style: TextStyle(
              fontSize: 11,
              color: barColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _timelineDescription(DateTime now) {
    final allowed = deadline.difference(submittedAt);
    final elapsed = now.difference(submittedAt);
    return 'Elapsed: ${_formatDuration(elapsed)} of '
        '${_formatDuration(allowed)} allowed';
  }

  String _formatDuration(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    if (safeDuration.inDays > 0) {
      final hours = safeDuration.inHours.remainder(24);
      return hours == 0
          ? '${safeDuration.inDays} day${safeDuration.inDays == 1 ? '' : 's'}'
          : '${safeDuration.inDays}d ${hours}h';
    }
    if (safeDuration.inHours > 0) {
      return '${safeDuration.inHours}h '
          '${safeDuration.inMinutes.remainder(60)}m';
    }
    return '${safeDuration.inMinutes}m';
  }
}
