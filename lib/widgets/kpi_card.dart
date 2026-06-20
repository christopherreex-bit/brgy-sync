import 'package:flutter/material.dart';
import '../utils/constants.dart';

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? accentColor;
  final IconData? icon;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.accentColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? kNavy;
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
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
