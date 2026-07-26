import 'package:brgysync_app/utils/budget_health.dart';
import 'package:brgysync_app/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expected remaining budget checkpoints', () {
    test('uses the Q1 targets from the schedule', () {
      expect(
        expectedRemainingBudgetPercent(
          fiscalYear: 2026,
          quarter: 1,
          asOf: DateTime(2026, 1, 14),
        ),
        100,
      );
      expect(
        expectedRemainingBudgetPercent(
          fiscalYear: 2026,
          quarter: 1,
          asOf: DateTime(2026, 1, 15),
        ),
        83,
      );
      expect(
        expectedRemainingBudgetPercent(
          fiscalYear: 2026,
          quarter: 1,
          asOf: DateTime(2026, 2, 28),
        ),
        33,
      );
      expect(
        expectedRemainingBudgetPercent(
          fiscalYear: 2026,
          quarter: 1,
          asOf: DateTime(2026, 3, 31),
        ),
        0,
      );
    });

    test('repeats the same schedule for Q3', () {
      expect(
        expectedRemainingBudgetPercent(
          fiscalYear: 2026,
          quarter: 3,
          asOf: DateTime(2026, 7, 27),
        ),
        83,
      );
    });
  });

  group('budget health', () {
    test('is healthy when remaining budget meets the checkpoint target', () {
      expect(
        calculateBudgetHealth(
          allocated: 1000,
          utilized: 150,
          fiscalYear: 2026,
          quarter: 3,
          asOf: DateTime(2026, 7, 27),
        ),
        budgetHealthy,
      );
    });

    test('is low when no more than one checkpoint behind', () {
      expect(
        calculateBudgetHealth(
          allocated: 1000,
          utilized: 300,
          fiscalYear: 2026,
          quarter: 3,
          asOf: DateTime(2026, 7, 27),
        ),
        budgetLow,
      );
    });

    test('is critical when more than one checkpoint behind', () {
      expect(
        calculateBudgetHealth(
          allocated: 1000,
          utilized: 500,
          fiscalYear: 2026,
          quarter: 3,
          asOf: DateTime(2026, 7, 27),
        ),
        budgetCritical,
      );
    });

    test('annual status uses the worst quarterly result', () {
      expect(
        worstBudgetHealth([budgetHealthy, budgetLow, budgetHealthy]),
        budgetLow,
      );
      expect(
        worstBudgetHealth([budgetHealthy, budgetCritical, budgetLow]),
        budgetCritical,
      );
    });
  });
}
