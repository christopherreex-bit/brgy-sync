import 'constants.dart';

const List<double> _checkpointTargets = [83, 67, 50, 33, 17, 0];

double expectedRemainingBudgetPercent({
  required int fiscalYear,
  required int quarter,
  required DateTime asOf,
}) {
  if (quarter < 1 || quarter > 4) return 100;

  final startMonth = 1 + ((quarter - 1) * 3);
  final quarterStart = DateTime(fiscalYear, startMonth);
  final quarterEnd = DateTime(fiscalYear, startMonth + 3);
  final date = DateTime(asOf.year, asOf.month, asOf.day);

  if (date.isBefore(quarterStart)) return 100;
  if (!date.isBefore(quarterEnd)) return 0;

  final checkpoints = <DateTime>[
    DateTime(fiscalYear, startMonth, 15),
    DateTime(fiscalYear, startMonth + 1, 0),
    DateTime(fiscalYear, startMonth + 1, 15),
    DateTime(fiscalYear, startMonth + 2, 0),
    DateTime(fiscalYear, startMonth + 2, 15),
    DateTime(fiscalYear, startMonth + 3, 0),
  ];

  var expected = 100.0;
  for (var index = 0; index < checkpoints.length; index++) {
    if (date.isBefore(checkpoints[index])) break;
    expected = _checkpointTargets[index];
  }
  return expected;
}

String calculateBudgetHealth({
  required double allocated,
  required double utilized,
  required int fiscalYear,
  required int quarter,
  required DateTime asOf,
}) {
  if (allocated <= 0) return budgetHealthy;

  final actualRemainingPercent = ((allocated - utilized) / allocated) * 100;
  if (actualRemainingPercent < 0) return budgetCritical;

  final expectedRemainingPercent = expectedRemainingBudgetPercent(
    fiscalYear: fiscalYear,
    quarter: quarter,
    asOf: asOf,
  );
  final shortfall = expectedRemainingPercent - actualRemainingPercent;

  if (shortfall <= 0.000001) return budgetHealthy;
  if (shortfall <= 17) return budgetLow;
  return budgetCritical;
}

String worstBudgetHealth(Iterable<String> statuses) {
  var result = budgetHealthy;
  for (final status in statuses) {
    if (status == budgetCritical) return budgetCritical;
    if (status == budgetLow) result = budgetLow;
  }
  return result;
}
