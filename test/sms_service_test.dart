import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/services/twilio_service.dart';

void main() {
  final sms = TwilioService();

  group('Philippine SMS recipient validation', () {
    test('accepts local and international Philippine mobile formats', () {
      expect(sms.isValidPhilippineMobile('0917 123 4567'), isTrue);
      expect(sms.isValidPhilippineMobile('+63 917 123 4567'), isTrue);
      expect(sms.isValidPhilippineMobile('639171234567'), isTrue);
    });

    test('rejects incomplete, landline, and non-Philippine numbers', () {
      expect(sms.isValidPhilippineMobile('0917123456'), isFalse);
      expect(sms.isValidPhilippineMobile('0281234567'), isFalse);
      expect(sms.isValidPhilippineMobile('+1 202 555 0100'), isFalse);
      expect(sms.isValidPhilippineMobile('not a number'), isFalse);
    });

    test('normalizes local numbers to E.164', () {
      expect(sms.formatPhoneNumber('0917-123-4567'), '+639171234567');
      expect(sms.formatPhoneNumber('+63 917 123 4567'), '+639171234567');
    });
  });
}
