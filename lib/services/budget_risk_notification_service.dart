import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/budget_health.dart';
import '../utils/budget_period.dart';
import '../utils/constants.dart';
import '../utils/money_formatter.dart';

class BudgetRiskNotificationService {
  final FirebaseFirestore _db;

  BudgetRiskNotificationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<void> notifyIfNeeded({
    required String programId,
    required String createdById,
    DateTime? asOf,
  }) async {
    if (programId.isEmpty) return;
    final date = asOf ?? DateTime.now();
    final program = await _db.collection('budgetPrograms').doc(programId).get();
    if (!program.exists) return;
    final data = program.data()!;
    final allocated = (data['allocated'] as num?)?.toDouble() ?? 0;
    final utilized = (data['utilized'] as num?)?.toDouble() ?? 0;
    final reserved = (data['reserved'] as num?)?.toDouble() ?? 0;
    final period = BudgetPeriod.fromData(data);
    final status = calculateBudgetHealth(
      allocated: allocated,
      utilized: utilized + reserved,
      fiscalYear: period.fiscalYear ?? date.year,
      quarter: period.quarter ?? 1,
      asOf: date,
    );
    if (status != budgetLow && status != budgetCritical) return;

    final notification = _db
        .collection('notifications')
        .doc('budget_risk_${programId}_$status');
    await _db.runTransaction((transaction) async {
      if ((await transaction.get(notification)).exists) return;
      final name = (data['name'] ?? 'Budget program').toString();
      final remaining = allocated - utilized - reserved;
      transaction.set(notification, {
        'type': status == budgetCritical ? 'budget_critical' : 'budget_low',
        'title': status == budgetCritical
            ? 'Critical program budget'
            : 'Program budget running low',
        'message':
            '$name has ${formatPeso(remaining)} available for ${period.label}. Review the allocation and pending releases.',
        'caseId': '',
        'referenceNumber': '',
        'recipientId': '',
        'audienceRoles': const ['captain', 'treasurer'],
        'createdById': createdById,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String>[],
        'deletedBy': <String>[],
        'programId': programId,
        'fiscalYear': period.fiscalYear,
        'quarter': period.quarter,
        'remaining': remaining,
        'budgetStatus': status,
      });
    });
  }
}
