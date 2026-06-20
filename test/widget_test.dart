import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BrgySyncApp());
    await tester.pumpAndSettle();
    // Should show login screen
    expect(find.text('BrgySync'), findsWidgets);
  });
}
