import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/utils/sla_calculator.dart';

void main() {
  test('Firestore SLA configuration overrides the default deadline', () {
    final config = buildSlaConfig([
      {'category': 'documents', 'deadlineValue': 45, 'deadlineUnit': 'minutes'},
    ]);
    final submitted = DateTime(2026, 7, 26, 8);

    final deadline = computeDeadline(
      submitted,
      'documents',
      'Barangay Clearance',
      config: config,
    );

    expect(deadline, DateTime(2026, 7, 26, 8, 45));
  });

  test('missing Firestore rules retain application defaults', () {
    final config = buildSlaConfig(const []);
    final submitted = DateTime(2026, 7, 26, 8);

    final deadline = computeDeadline(
      submitted,
      'documents',
      'Barangay Clearance',
      config: config,
    );

    expect(deadline, DateTime(2026, 7, 26, 8, 15));
  });

  test('BASS medical configuration applies to medical subtype variants', () {
    final config = buildSlaConfig([
      {
        'category': 'bass_medical',
        'deadlineValue': 10,
        'deadlineUnit': 'working_days',
      },
    ]);
    final submitted = DateTime(2026, 7, 27, 8);

    final deadline = computeDeadline(
      submitted,
      'bass',
      'Medical - Dialysis',
      config: config,
    );

    expect(deadline, DateTime(2026, 8, 10, 8));
  });
}
