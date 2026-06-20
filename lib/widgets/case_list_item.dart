import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'status_badge.dart';

class CaseListItem extends StatelessWidget {
  final String referenceNumber;
  final String category;
  final String residentName;
  final String subType;
  final DateTime submittedAt;
  final String status;
  final bool isConfidential;
  final VoidCallback? onTap;

  const CaseListItem({
    super.key,
    required this.referenceNumber,
    required this.category,
    required this.residentName,
    required this.subType,
    required this.submittedAt,
    required this.status,
    this.isConfidential = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = isConfidential ? 'Confidential' : residentName;
    final dateStr =
        '${submittedAt.month}/${submittedAt.day}/${submittedAt.year} ${submittedAt.hour.toString().padLeft(2, '0')}:${submittedAt.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(referenceNumber,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: kNavy, fontSize: 13)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(category.toUpperCase(),
                            style: const TextStyle(fontSize: 9, color: kNavy, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('$displayName · $subType · $dateStr',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),
            StatusBadge(status: status),
          ],
        ),
      ),
    );
  }
}
