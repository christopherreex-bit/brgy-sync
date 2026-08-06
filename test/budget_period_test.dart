import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/utils/budget_period.dart';

void main() {
  test('annual fiscal period is parsed as the parent year', () {
    final period = BudgetPeriod.parse('FY 2026');

    expect(period.fiscalYear, 2026);
    expect(period.type, 'annual');
    expect(period.quarter, isNull);
    expect(period.scopeLabel, 'Annual');
  });

  test('legacy quarterly label is placed under its fiscal year', () {
    final period = BudgetPeriod.parse('FY 2026 Q2 (Apr–Jun)');

    expect(period.fiscalYear, 2026);
    expect(period.type, 'quarterly');
    expect(period.quarter, 2);
    expect(period.scopeLabel, 'Q2');
  });

  test('structured fields take precedence over legacy label parsing', () {
    final period = BudgetPeriod.fromData({
      'fiscalPeriod': 'Second Quarter',
      'fiscalYear': 2027,
      'periodType': 'quarterly',
      'quarter': 2,
    });

    expect(period.fiscalYear, 2027);
    expect(period.type, 'quarterly');
    expect(period.quarter, 2);
  });

  test(
    'past fiscal quarters are locked but current quarter remains editable',
    () {
      final asOf = DateTime(2026, 8, 6); // Q3

      expect(
        isPastBudgetQuarter(BudgetPeriod.parse('FY 2026 Q2'), asOf),
        isTrue,
      );
      expect(
        isPastBudgetQuarter(BudgetPeriod.parse('FY 2026 Q3'), asOf),
        isFalse,
      );
      expect(
        isPastBudgetQuarter(BudgetPeriod.parse('FY 2026 Q4'), asOf),
        isFalse,
      );
      expect(
        isPastBudgetQuarter(BudgetPeriod.parse('FY 2025 Q4'), asOf),
        isTrue,
      );
    },
  );
}
