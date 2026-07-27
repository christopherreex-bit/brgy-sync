import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/utils/account_validators.dart';

void main() {
  test('valid account details pass validation', () {
    expect(validateAccountEmail('staff@example.com'), isNull);
    expect(validatePhilippineMobile('09123456789'), isNull);
    expect(validateStaffPassword('simple'), isNull);
  });

  test('invalid email and mobile formats are rejected', () {
    expect(validateAccountEmail('staff@example'), isNotNull);
    expect(validatePhilippineMobile('9123456789'), isNotNull);
    expect(validatePhilippineMobile('091234567890'), isNotNull);
  });

  test('password only requires six characters', () {
    expect(validateStaffPassword('12345'), isNotNull);
    expect(validateStaffPassword('123456'), isNull);
    expect(validateStaffPassword('abcdef'), isNull);
  });

  test('changed password must differ from the current password', () {
    expect(
      validatePasswordChange(
        currentPassword: 'secret1',
        newPassword: 'secret1',
      ),
      isNotNull,
    );
    expect(
      validatePasswordChange(
        currentPassword: 'secret1',
        newPassword: 'secret2',
      ),
      isNull,
    );
  });
}
