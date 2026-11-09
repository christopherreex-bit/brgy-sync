import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/models/service_category.dart';

void main() {
  test('barangay clearance uses a required purpose dropdown', () {
    final purpose = formFieldsFor(
      'documents',
      'Barangay Clearance',
    ).singleWhere((field) => field.key == 'purpose');

    expect(purpose.type, FormFieldType.dropdown);
    expect(purpose.required, isTrue);
    expect(purpose.options, contains('Employment / Job Application'));
    expect(purpose.options, contains('Other Official Purpose'));
  });

  test('self-filed indigency does not ask for a representative', () {
    final fields = formFieldsFor('documents', 'Indigency Certificate');
    final keys = fields.map((field) => field.key);

    expect(keys, containsAll(<String>['beneficiaryName', 'address']));
    expect(keys, isNot(contains('guardianName')));
    expect(keys, isNot(contains('relationship')));
  });

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
