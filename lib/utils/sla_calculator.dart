import '../models/service_category.dart';

/// Philippine public holidays for a given year.
/// Covers fixed-date national holidays. Movable holidays (Easter, Eid) are not included.
/// For production, consider using a proper holiday API.
Set<String> _philippineHolidaysForYear(int year) {
  return {
    '$year-01-01', // New Year's Day
    '$year-02-25', // EDSA People Power Revolution
    '$year-04-09', // Araw ng Kagitingan
    '$year-05-01', // Labor Day
    '$year-06-12', // Independence Day
    '$year-08-21', // Ninoy Aquino Day
    '$year-11-01', // All Saints' Day
    '$year-11-30', // Bonifacio Day
    '$year-12-08', // Immaculate Conception
    '$year-12-25', // Christmas Day
    '$year-12-30', // Rizal Day
    '$year-12-31', // Last Day of the Year
    // Movable: Maundy Thursday & Good Friday (Easter-based) — approximate for year
    ..._easterHolidays(year),
  };
}

/// Compute Maundy Thursday and Good Friday for a given year.
/// Uses the Anonymous Gregorian algorithm for Easter calculation.
List<String> _easterHolidays(int year) {
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
  final month = (h + l - 7 * m + 114) ~/ 31; // 3=March, 4=April
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  final easter = DateTime(year, month, day);
  final maundyThursday = easter.subtract(const Duration(days: 3));
  final goodFriday = easter.subtract(const Duration(days: 2));
  return [
    '${maundyThursday.year}-${maundyThursday.month.toString().padLeft(2, '0')}-${maundyThursday.day.toString().padLeft(2, '0')}',
    '${goodFriday.year}-${goodFriday.month.toString().padLeft(2, '0')}-${goodFriday.day.toString().padLeft(2, '0')}',
  ];
}

/// Returns the set of holiday date strings for the current year.
Set<String> get currentHolidays => _philippineHolidaysForYear(DateTime.now().year);

/// Compute the SLA deadline from a submission timestamp.
DateTime computeDeadline(DateTime submitted, String category, String subType) {
  final slaKey = slaKeyFor(category, subType);
  final sla = kSlaDefaults[slaKey]!;
  final value = sla['value'] as int;
  final unit = sla['unit'] as String;

  if (unit == 'minutes') {
    return submitted.add(Duration(minutes: value));
  }

  // Working days: Mon–Fri, skip holidays
  final holidays = _philippineHolidaysForYear(submitted.year);
  DateTime current = submitted;
  int daysAdded = 0;
  while (daysAdded < value) {
    current = current.add(const Duration(days: 1));
    final dow = current.weekday;
    if (dow == DateTime.saturday || dow == DateTime.sunday) continue;
    final key = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
    if (holidays.contains(key)) continue;
    daysAdded++;
  }
  return current;
}

/// Compute SLA status based on current time vs deadline.
String computeSLAStatus(DateTime deadline) {
  final now = DateTime.now();
  final diff = deadline.difference(now);
  if (diff.isNegative) return 'overdue';
  if (diff.inHours < 24) return 'near_deadline';
  return 'on_time';
}

/// Human-readable time remaining string.
String timeRemainingString(DateTime deadline) {
  final now = DateTime.now();
  final diff = deadline.difference(now);
  if (diff.isNegative) {
    final overdue = now.difference(deadline);
    if (overdue.inDays > 0) return '+${overdue.inDays} days overdue';
    if (overdue.inHours > 0) return '+${overdue.inHours}h overdue';
    return '+${overdue.inMinutes}m overdue';
  }
  if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h remaining';
  if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m remaining';
  return '${diff.inMinutes}m remaining';
}
