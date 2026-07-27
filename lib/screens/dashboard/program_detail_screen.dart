import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../utils/budget_health.dart';
import '../../utils/budget_period.dart';
import '../../utils/constants.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status_badge.dart';

class ProgramDetailScreen extends StatelessWidget {
  final String? programId;
  final String? programName;
  final int? fiscalYear;
  final int? quarter;

  const ProgramDetailScreen({
    super.key,
    this.programId,
    this.programName,
    this.fiscalYear,
    this.quarter,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('budgetPrograms')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load budget details: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final programs = _selectPrograms(snapshot.data?.docs ?? []);
        final displayName =
            programName ??
            (programs.isNotEmpty
                ? (programs.first.data()['name'] ?? '').toString()
                : 'Budget Program');
        final allocated = programs.fold<double>(
          0,
          (total, doc) =>
              total + ((doc.data()['allocated'] as num?)?.toDouble() ?? 0),
        );
        final utilized = programs.fold<double>(
          0,
          (total, doc) =>
              total + ((doc.data()['utilized'] as num?)?.toDouble() ?? 0),
        );
        final remaining = allocated - utilized;
        final statuses = programs.map((doc) {
          final data = doc.data();
          final period = BudgetPeriod.fromData(data);
          return calculateBudgetHealth(
            allocated: (data['allocated'] as num?)?.toDouble() ?? 0,
            utilized: (data['utilized'] as num?)?.toDouble() ?? 0,
            fiscalYear: period.fiscalYear ?? fiscalYear ?? DateTime.now().year,
            quarter: period.quarter ?? quarter ?? 1,
            asOf: DateTime.now(),
          );
        });
        final status = worstBudgetHealth(statuses);
        final scope = quarter == null
            ? 'FY ${fiscalYear ?? ''} Annual'
            : 'FY ${fiscalYear ?? ''} Q$quarter';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => context.go('/dashboard/budget'),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Budget Overview'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: kNavy,
                      ),
                    ),
                  ),
                  StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 4),
              Text(scope, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: KpiCard(
                      label: 'Allocated',
                      value: '₱${allocated.toStringAsFixed(0)}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KpiCard(
                      label: 'Utilized',
                      value: '₱${utilized.toStringAsFixed(0)}',
                      accentColor: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KpiCard(
                      label: 'Remaining',
                      value: '₱${remaining.toStringAsFixed(0)}',
                      accentColor: remaining < 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Budget Deductions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kNavy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Amounts automatically subtracted when assistance cases are released. Select a row to view the case.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (programs.isEmpty)
                const _EmptyTransactions(
                  message: 'No allocation is configured for this period.',
                )
              else
                _TransactionList(
                  programIds: programs.map((doc) => doc.id).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _selectPrograms(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    if (programId != null) {
      return allDocs.where((doc) => doc.id == programId).toList();
    }

    final latestByQuarter =
        <int, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in allDocs) {
      final data = doc.data();
      if ((data['name'] ?? '').toString().trim().toLowerCase() !=
          programName?.trim().toLowerCase()) {
        continue;
      }
      final period = BudgetPeriod.fromData(data);
      if (period.type != 'quarterly' ||
          period.fiscalYear != fiscalYear ||
          (quarter != null && period.quarter != quarter)) {
        continue;
      }
      final periodQuarter = period.quarter;
      if (periodQuarter == null) continue;
      final existing = latestByQuarter[periodQuarter];
      if (existing == null ||
          _lastUpdated(data) > _lastUpdated(existing.data()) ||
          (_lastUpdated(data) == _lastUpdated(existing.data()) &&
              doc.id.compareTo(existing.id) > 0)) {
        latestByQuarter[periodQuarter] = doc;
      }
    }
    return latestByQuarter.values.toList()..sort((a, b) {
      final aQuarter = BudgetPeriod.fromData(a.data()).quarter ?? 0;
      final bQuarter = BudgetPeriod.fromData(b.data()).quarter ?? 0;
      return aQuarter.compareTo(bQuarter);
    });
  }

  int _lastUpdated(Map<String, dynamic> data) {
    return (data['lastUpdated'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
  }
}

class _TransactionList extends StatelessWidget {
  final List<String> programIds;

  const _TransactionList({required this.programIds});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'budgetTransactions',
    );
    query = programIds.length == 1
        ? query.where('programId', isEqualTo: programIds.first)
        : query.where('programId', whereIn: programIds);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text(
            'Could not load deductions: ${snapshot.error}',
            style: const TextStyle(color: Colors.red),
          );
        }
        final transactions = snapshot.data?.docs ?? [];
        if (transactions.isEmpty) {
          return const _EmptyTransactions(
            message: 'No budget deductions have been recorded yet.',
          );
        }

        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _loadCases(transactions),
          builder: (context, caseSnapshot) {
            final cases = caseSnapshot.data ?? {};
            return Column(
              children: transactions.map((transaction) {
                final data = transaction.data();
                final caseId = (data['caseId'] ?? '').toString();
                final caseData = cases[caseId] ?? const <String, dynamic>{};
                final referenceNumber =
                    (data['referenceNumber'] ??
                            caseData['referenceNumber'] ??
                            caseId)
                        .toString();
                final residentName =
                    (data['residentName'] ??
                            caseData['residentName'] ??
                            'Name unavailable')
                        .toString();
                final amount = (data['amount'] as num?)?.toDouble() ?? 0;
                final timestamp = data['timestamp'] is Timestamp
                    ? (data['timestamp'] as Timestamp).toDate()
                    : null;
                final date = timestamp == null
                    ? 'Date unavailable'
                    : '${timestamp.month}/${timestamp.day}/${timestamp.year}';
                final transactionQuarter = (data['quarter'] as num?)?.toInt();
                final transactionYear = (data['fiscalYear'] as num?)?.toInt();
                final period = transactionYear == null
                    ? ''
                    : ' · FY $transactionYear'
                          '${transactionQuarter == null ? '' : ' Q$transactionQuarter'}';

                return InkWell(
                  onTap: caseId.isEmpty
                      ? null
                      : () => context.go('/dashboard/case/$caseId'),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long, color: kNavy),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                referenceNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kNavy,
                                ),
                              ),
                              Text(
                                residentName,
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '$date$period',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '-₱${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (caseId.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadCases(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> transactions,
  ) async {
    final caseIds = transactions
        .map((doc) => (doc.data()['caseId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    final result = <String, Map<String, dynamic>>{};
    await Future.wait(
      caseIds.map((caseId) async {
        final snapshot = await FirebaseFirestore.instance
            .collection('cases')
            .doc(caseId)
            .get();
        if (snapshot.exists && snapshot.data() != null) {
          result[caseId] = snapshot.data()!;
        }
      }),
    );
    return result;
  }
}

class _EmptyTransactions extends StatelessWidget {
  final String message;

  const _EmptyTransactions({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}
