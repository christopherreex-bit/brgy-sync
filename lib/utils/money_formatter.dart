import 'package:intl/intl.dart';

/// Formats Philippine peso amounts consistently with thousands separators.
String formatPeso(num value, {int decimalDigits = 2}) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: decimalDigits,
  ).format(value);
}

/// Formats a monetary number without adding the peso symbol.
String formatMoneyNumber(num value, {int decimalDigits = 2}) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '',
    decimalDigits: decimalDigits,
  ).format(value).trim();
}
