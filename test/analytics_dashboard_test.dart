import 'package:brgysync_app/screens/dashboard/analytics_dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category bars use total cases as their denominator', () {
    expect(calculateCategoryShare(2, 3), closeTo(2 / 3, 0.000001));
    expect(calculateCategoryShare(1, 3), closeTo(1 / 3, 0.000001));
  });

  test('category share safely handles empty and invalid totals', () {
    expect(calculateCategoryShare(0, 0), 0);
    expect(calculateCategoryShare(1, 0), 0);
  });
}
