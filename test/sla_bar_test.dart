import 'package:brgysync_app/widgets/sla_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders an active SLA timeline', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlaBar(
            slaStatus: 'on_time',
            timeRemaining: '30m remaining',
            submittedAt: now.subtract(const Duration(minutes: 30)),
            deadline: now.add(const Duration(minutes: 30)),
          ),
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.backgroundColor, const Color(0xFFDCFCE7));
    expect(
      (progress.valueColor! as AlwaysStoppedAnimation<Color?>).value,
      const Color(0xFF16A34A),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an overdue SLA timeline', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlaBar(
            slaStatus: 'overdue',
            timeRemaining: '+15m overdue',
            submittedAt: now.subtract(const Duration(minutes: 30)),
            deadline: now.subtract(const Duration(minutes: 15)),
          ),
        ),
      ),
    );

    expect(find.text('+15m overdue'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.backgroundColor, const Color(0xFFFEE2E2));
    expect(
      (progress.valueColor! as AlwaysStoppedAnimation<Color?>).value,
      const Color(0xFFEF4444),
    );
    expect(tester.takeException(), isNull);
  });
}
