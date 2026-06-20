import 'package:flutter/material.dart';
import '../utils/constants.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final bg = statusBadgeBg[status] ?? Colors.grey.shade200;
    final fg = statusBadgeText[status] ?? Colors.grey.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _formatLabel(status),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  static String _formatLabel(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
