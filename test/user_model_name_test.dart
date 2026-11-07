import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/models/user_model.dart';

void main() {
  test('structured names compose into the display name', () {
    final user = UserModel.fromMap({
      'firstName': 'Juan',
      'middleName': 'Santos',
      'lastName': 'Dela Cruz',
      'mobile': '09171234567',
      'email': 'juan@example.com',
      'role': 'resident',
    }, 'resident-1');

    expect(user.name, 'Juan Santos Dela Cruz');
    expect(user.firstName, 'Juan');
    expect(user.middleName, 'Santos');
    expect(user.lastName, 'Dela Cruz');
  });

  test('legacy full names remain readable', () {
    final user = UserModel.fromMap({
      'name': 'Maria Reyes',
      'mobile': '09181234567',
      'email': 'maria@example.com',
      'role': 'resident',
    }, 'resident-2');

    expect(user.name, 'Maria Reyes');
    expect(user.firstName, 'Maria');
    expect(user.middleName, '');
    expect(user.lastName, 'Reyes');
  });

  test('middle initial is optional', () {
    expect(
      UserModel.composeName(firstName: 'Ana', lastName: 'Santos'),
      'Ana Santos',
    );
  });
}
