import '../models/service_category.dart';

/// Philippine public holidays 2026 (fixed dates only — excludes movable like Easter).
/// For production, use a proper holiday API or a full list.
const Set<String> kPhilippineHolidays2026 = {
  '2026-01-01', // New Year's Day
  '2026-02-25', // EDSA People Power Revolution
  '2026-04-09', // Araw ng Kagitingan
  '2026-04-16', // Maundy Thursday
  '2026-04-17', // Good Friday
  '2026-05-01', // Labor Day
  '2026-06-12', // Independence Day
  '2026-08-21', // Ninoy Aquino Day
  '2026-08-31', // National Heroes Day (last Mon of Aug)
  '2026-11-01', // All Saints' Day
  '2026-11-30', // Bonifacio Day
  '2026-12-08', // Immaculate Conception
  '2026-12-25', // Christmas Day
  '2026-12-30', // Rizal Day
  '2026-12-31', // Last Day of the Year
};

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
  DateTime current = submitted;
  int daysAdded = 0;
  while (daysAdded < value) {
    current = current.add(const Duration(days: 1));
    final dow = current.weekday;
    if (dow == DateTime.saturday || dow == DateTime.sunday) continue;
    final key = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
    if (kPhilippineHolidays2026.contains(key)) continue;
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
