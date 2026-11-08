import 'package:brgysync_app/utils/philippine_business_calendar.dart';
import 'package:brgysync_app/services/cash_position_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhilippineBusinessCalendar bank-to-cash schedule', () {
    test('regular weekday starts immediately and arrives next weekday', () {
      final request = DateTime(2026, 11, 9, 10, 30); // Monday
      final schedule = PhilippineBusinessCalendar.bankToCashSchedule(request);

      expect(schedule.startsAt, request);
      expect(schedule.arrivesAt, DateTime(2026, 11, 10, 10, 30));
    });

    test('Saturday request starts Monday and arrives Tuesday', () {
      final schedule = PhilippineBusinessCalendar.bankToCashSchedule(
        DateTime(2026, 11, 7, 9),
      );

      expect(schedule.startsAt, DateTime(2026, 11, 9, 9));
      expect(schedule.arrivesAt, DateTime(2026, 11, 10, 9));
    });

    test('Friday request arrives on the next banking day', () {
      final schedule = PhilippineBusinessCalendar.bankToCashSchedule(
        DateTime(2026, 11, 13, 14),
      );

      expect(schedule.startsAt, DateTime(2026, 11, 13, 14));
      // Nov 16-18, 2026 are NCR-wide special non-working days.
      expect(schedule.arrivesAt, DateTime(2026, 11, 19, 14));
    });

    test('NCR holiday request waits until the next banking day', () {
      final schedule = PhilippineBusinessCalendar.bankToCashSchedule(
        DateTime(2026, 11, 16, 8),
      );

      expect(schedule.startsAt, DateTime(2026, 11, 19, 8));
      expect(schedule.arrivesAt, DateTime(2026, 11, 20, 8));
    });

    test('Christmas request skips holiday and weekend', () {
      final schedule = PhilippineBusinessCalendar.bankToCashSchedule(
        DateTime(2026, 12, 25, 11),
      );

      expect(schedule.startsAt, DateTime(2026, 12, 28, 11));
      expect(schedule.arrivesAt, DateTime(2026, 12, 29, 11));
    });

    test('special working EDSA anniversary remains a business day', () {
      expect(
        PhilippineBusinessCalendar.isBusinessDay(DateTime(2026, 2, 25)),
        isTrue,
      );
    });
  });

  group('cash liquidity alert assessment', () {
    test('uses 20 percent of undisbursed current-quarter budget', () {
      final result = CashPositionService.assessLiquidity(
        cashInBank: 50000,
        cashOnHand: 5000,
        cashInTransit: 0,
        reserved: 3000,
        undisbursedBudget: 50000,
      );

      expect(result.needsBankTransfer, isTrue);
      expect(result.targetCashOnHand, 10000);
      expect(result.suggestedTransfer, 5000);
    });

    test('reserved payouts override the percentage threshold', () {
      final result = CashPositionService.assessLiquidity(
        cashInBank: 50000,
        cashOnHand: 5000,
        cashInTransit: 2000,
        reserved: 12000,
        undisbursedBudget: 50000,
      );

      expect(result.needsBankTransfer, isTrue);
      expect(result.targetCashOnHand, 12000);
      expect(result.suggestedTransfer, 5000);
    });

    test('does not alert when cash plus funds in transit cover target', () {
      final result = CashPositionService.assessLiquidity(
        cashInBank: 50000,
        cashOnHand: 6000,
        cashInTransit: 4000,
        reserved: 3000,
        undisbursedBudget: 50000,
      );

      expect(result.needsBankTransfer, isFalse);
      expect(result.suggestedTransfer, 0);
    });
  });
}
