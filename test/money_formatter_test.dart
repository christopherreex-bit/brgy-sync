import 'package:brgysync_app/utils/money_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('peso values include thousands separators', () {
    expect(formatPeso(1000000), '₱1,000,000.00');
    expect(formatPeso(1000, decimalDigits: 0), '₱1,000');
    expect(formatMoneyNumber(12500, decimalDigits: 0), '12,500');
  });
}
