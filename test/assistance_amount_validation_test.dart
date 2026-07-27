import 'package:brgysync_app/models/service_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final assistanceAmount = formFieldsFor(
    'bass',
    'Medical Assistance',
  ).firstWhere((field) => field.key == 'assistanceAmount');

  test('BASS assistance amount is required', () {
    expect(assistanceAmount.required, isTrue);
    expect(
      validateField(assistanceAmount, '', null, null, null),
      'Assistance Amount (₱) is required.',
    );
  });

  test('BASS assistance amount must be numeric', () {
    expect(
      validateField(assistanceAmount, 'not a number', null, null, null),
      'Must be a valid number.',
    );
    expect(validateField(assistanceAmount, '1500', null, null, null), isNull);
  });
}
