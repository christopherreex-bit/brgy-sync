import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/models/service_category.dart';

void main() {
  group('beneficiary birthday age requirements', () {
    test('senior citizen applications require a minimum age of 60', () {
      final fields = formFieldsFor(
        'beneficiary',
        'Senior Citizen Birthday Program',
      );
      final birthday = fields.firstWhere((field) => field.key == 'birthday');

      expect(birthday.minAge, 60);
    });

    test('PWD applications do not require a minimum age', () {
      final fields = formFieldsFor('beneficiary', 'PWD Birthday Program');
      final birthday = fields.firstWhere((field) => field.key == 'birthday');

      expect(birthday.minAge, isNull);
    });
  });
}
