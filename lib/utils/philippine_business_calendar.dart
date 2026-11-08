/// Philippine banking-day rules used for bank-to-cash transit estimates.
///
/// Saturdays, Sundays, national regular holidays, national special
/// non-working days, and configured NCR-wide non-working days are excluded.
/// Special working days (for example, EDSA anniversary) are intentionally not
/// excluded.
class PhilippineBusinessCalendar {
  const PhilippineBusinessCalendar._();

  static bool isBusinessDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    return !holidaysForYear(date.year).contains(_dateKey(date));
  }

  /// Returns the next Philippine banking day after [date].
  ///
  /// The original time of day is preserved.
  static DateTime nextBusinessDay(DateTime date) {
    var candidate = date.add(const Duration(days: 1));
    while (!isBusinessDay(candidate)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// Computes when processing starts and when funds should reach cash on hand.
  ///
  /// A request made on a banking day starts immediately. A request made on a
  /// weekend or holiday starts on the next banking day. Arrival is one full
  /// banking day after the start.
  static BankTransferSchedule bankToCashSchedule(DateTime requestedAt) {
    final startsAt = isBusinessDay(requestedAt)
        ? requestedAt
        : _nextBusinessDayIncludingCurrent(requestedAt);
    return BankTransferSchedule(
      startsAt: startsAt,
      arrivesAt: nextBusinessDay(startsAt),
    );
  }

  static DateTime _nextBusinessDayIncludingCurrent(DateTime date) {
    var candidate = date;
    while (!isBusinessDay(candidate)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  static Set<String> holidaysForYear(int year) {
    final holidays = <String>{
      _key(year, 1, 1), // New Year's Day
      _key(year, 4, 9), // Araw ng Kagitingan
      _key(year, 5, 1), // Labor Day
      _key(year, 6, 12), // Independence Day
      _dateKey(_lastMondayOfAugust(year)), // National Heroes Day
      _key(year, 8, 21), // Ninoy Aquino Day
      _key(year, 11, 1), // All Saints' Day
      _key(year, 11, 30), // Bonifacio Day
      _key(year, 12, 8), // Immaculate Conception
      _key(year, 12, 24), // Christmas Eve
      _key(year, 12, 25), // Christmas Day
      _key(year, 12, 30), // Rizal Day
      _key(year, 12, 31), // Last Day of the Year
      ..._holyWeekDates(year),
    };

    // Year-specific dates declared by presidential proclamation. Movable
    // Islamic and lunar holidays cannot be safely inferred from recurrence.
    holidays.addAll(_declaredHolidays[year] ?? const <String>{});
    return holidays;
  }

  static const Map<int, Set<String>> _declaredHolidays = {
    2026: {
      '2026-02-17', // Chinese New Year
      '2026-03-20', // Eid'l Fitr (Proclamation No. 1189)
      '2026-04-04', // Black Saturday
      '2026-05-27', // Eid'l Adha (Proclamation No. 1264)
      '2026-11-02', // All Souls' Day
      // NCR-wide ASEAN Summit non-working days (Proclamation No. 1447).
      '2026-11-16',
      '2026-11-17',
      '2026-11-18',
    },
    2027: {
      '2027-02-06', // Chinese New Year
      '2027-03-27', // Black Saturday
      '2027-11-02', // All Souls' Day
    },
  };

  static Set<String> _holyWeekDates(int year) {
    final easter = _easterSunday(year);
    return {
      _dateKey(easter.subtract(const Duration(days: 3))), // Maundy Thursday
      _dateKey(easter.subtract(const Duration(days: 2))), // Good Friday
    };
  }

  static DateTime _easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  static DateTime _lastMondayOfAugust(int year) {
    var date = DateTime(year, 8, 31);
    while (date.weekday != DateTime.monday) {
      date = date.subtract(const Duration(days: 1));
    }
    return date;
  }

  static String _dateKey(DateTime date) =>
      _key(date.year, date.month, date.day);

  static String _key(int year, int month, int day) =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

class BankTransferSchedule {
  final DateTime startsAt;
  final DateTime arrivesAt;

  const BankTransferSchedule({required this.startsAt, required this.arrivesAt});
}
