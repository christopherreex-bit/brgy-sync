import 'dart:convert';
import 'package:http/http.dart' as http;

/// Twilio SMS service.
///
/// Credentials are injected at build time via --dart-define:
///   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM
///
/// For demo/mock mode, set USE_MOCK_TWILIO=true via --dart-define
/// and SMS will be printed to console instead of sending.

class TwilioService {
  final String? _accountSid;
  final String? _authToken;
  final String? _fromNumber;
  final bool _mockMode;

  TwilioService()
      : _accountSid = const String.fromEnvironment('TWILIO_ACCOUNT_SID'),
        _authToken = const String.fromEnvironment('TWILIO_AUTH_TOKEN'),
        _fromNumber = const String.fromEnvironment('TWILIO_FROM'),
        _mockMode = const String.fromEnvironment('USE_MOCK_TWILIO') == 'true';

  /// Converts a Philippine mobile (09XXXXXXXXX) to +63 format.
  String formatPhoneNumber(String number) {
    final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('09')) return '+63${cleaned.substring(1)}';
    if (cleaned.startsWith('639')) return '+$cleaned';
    if (cleaned.startsWith('+639')) return cleaned;
    return cleaned;
  }

  /// Fallback verified number for trial accounts (Philippines).
  /// SMS is always sent directly to this verified number to avoid
  /// failed attempts to unverified numbers (which still incur charges).
  static const String _fallbackNumber = '+639397193163';

  /// Send an SMS. Always delivers to the verified fallback number
  /// to guarantee delivery on trial accounts without wasting credits
  /// on failed attempts to unverified numbers.
  /// Returns null on success, error message on failure.
  Future<String?> sendSms(String toNumber, String message) async {
    if (_mockMode || _accountSid == null || _authToken == null || _fromNumber == null) {
      // Mock mode: print to console (shows intended recipient)
      final intended = formatPhoneNumber(toNumber);
      print('[MOCK SMS] To: $intended | Message: $message');
      return null;
    }

    final url = Uri.parse(
      'https://api.twilio.com/2010-04-01/Accounts/$_accountSid/Messages.json',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_accountSid:$_authToken'))}',
        },
        body: {
          'From': _fromNumber,
          'To': _fallbackNumber,
          'Body': message,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return null; // success
      } else {
        return 'Twilio error: ${response.statusCode} ${response.body}';
      }
    } catch (e) {
      return 'Network error: $e';
    }
  }

  // ─── SMS Templates (6 types) ─────────────────────────────────────

  Future<String?> sendSubmissionAck(String mobile, String refNumber) async {
    return sendSms(mobile,
      'BrgySync: Your request has been submitted. Ref#: $refNumber. We will notify you on updates. Thank you!');
  }

  Future<String?> sendStatusProcessing(String mobile, String refNumber) async {
    return sendSms(mobile,
      'BrgySync: Your case $refNumber is now being processed. Thank you for your patience.');
  }

  Future<String?> sendStatusAwaitingDocs(String mobile, String refNumber) async {
    return sendSms(mobile,
      'BrgySync: Your case $refNumber requires additional documents. Please submit the missing items to the barangay hall.');
  }

  Future<String?> sendStatusApproved(String mobile, String refNumber) async {
    return sendSms(mobile,
      'BrgySync: Your case $refNumber has been approved. We will notify you when it is ready for release.');
  }

  Future<String?> sendStatusReleased(String mobile, String refNumber) async {
    return sendSms(mobile,
      'BrgySync: Your case $refNumber has been resolved/released. Please proceed to the barangay hall to claim.');
  }

  Future<String?> sendStatusRejected(String mobile, String refNumber) async {
    return sendSms(mobile,
      'BrgySync: Your case $refNumber has been reviewed and could not be approved. Please visit the barangay hall for details.');
  }
}
