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
  final bool awaitingCaptainApproval;
  final bool claimingApprovalRejected;
  final String claimingRejectionReason;
  final String claimingRejectedByName;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const CaseListItem({
    super.key,
    required this.referenceNumber,
    required this.category,
    required this.residentName,
    required this.subType,
    required this.submittedAt,
    required this.status,
    this.isConfidential = false,
    this.awaitingCaptainApproval = false,
    this.claimingApprovalRejected = false,
    this.claimingRejectionReason = '',
    this.claimingRejectedByName = '',
    this.onTap,
    this.onDelete,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        referenceNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kNavy,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            color: kNavy,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$displayName · $subType · $dateStr',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  if (awaitingCaptainApproval) ...[
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_top_rounded,
                            size: 14,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Pending Barangay Captain approval',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (claimingApprovalRejected) ...[
                    const SizedBox(height: 7),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade200),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            size: 16,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'For Claiming request rejected'
                                  '${claimingRejectedByName.trim().isEmpty ? '' : ' by $claimingRejectedByName'}',
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (claimingRejectionReason.trim().isNotEmpty)
                                  Text(
                                    'Reason: $claimingRejectionReason',
                                    style: TextStyle(
                                      color: Colors.red.shade800,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: StatusBadge(status: status),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete case',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
