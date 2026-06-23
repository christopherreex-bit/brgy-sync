import 'dart:convert';
import 'package:http/http.dart' as http;

/// SMS service using EasySendSMS as primary and Twilio as fallback.
///
/// EasySendSMS credentials injected at build time via --dart-define:
///   EASYSENDSMS_API_KEY
///
/// Twilio credentials injected at build time via --dart-define:
///   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM
///
/// For demo/mock mode, set USE_MOCK_SMS=true via --dart-define
/// and SMS will be printed to console instead of sending.

class TwilioService {
  final String? _easySendKey;
  final String? _twilioSid;
  final String? _twilioToken;
  final String? _twilioFrom;
  final bool _mockMode;

  TwilioService()
      : _easySendKey = const String.fromEnvironment('EASYSENDSMS_API_KEY'),
        _twilioSid = const String.fromEnvironment('TWILIO_ACCOUNT_SID'),
        _twilioToken = const String.fromEnvironment('TWILIO_AUTH_TOKEN'),
        _twilioFrom = const String.fromEnvironment('TWILIO_FROM'),
        _mockMode = const String.fromEnvironment('USE_MOCK_SMS') == 'true';

  /// Converts a Philippine mobile (09XXXXXXXXX) to +63 format.
  String formatPhoneNumber(String number) {
    final cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('09')) return '+63${cleaned.substring(1)}';
    if (cleaned.startsWith('639')) return '+$cleaned';
    if (cleaned.startsWith('+639')) return cleaned;
    return cleaned;
  }

  /// Send an SMS. Tries EasySendSMS first, falls back to Twilio.
  /// Returns null on success, error message on failure.
  Future<String?> sendSms(String toNumber, String message) async {
    final to = formatPhoneNumber(toNumber);

    if (_mockMode) {
      print('[MOCK SMS] To: $to | Message: $message');
      return null;
    }

    // ── Primary: EasySendSMS ──
    if (_easySendKey != null && _easySendKey!.isNotEmpty) {
      final result = await _sendEasySend(to, message);
      if (result == null) return null;
      print('[SMS] EasySendSMS failed: $result. Trying Twilio fallback...');
    }

    // ── Fallback: Twilio ──
    if (_twilioSid != null && _twilioToken != null && _twilioFrom != null) {
      return _sendTwilio(to, message);
    }

    return 'No SMS provider configured.';
  }

  /// Send via EasySendSMS REST API.
  /// Number must be digits only with country code, no + prefix (e.g. 639397193163).
  Future<String?> _sendEasySend(String to, String message) async {
    // Strip + prefix — EasySendSMS wants raw digits like 639397193163
    final digitsOnly = to.replaceAll(RegExp(r'[^\d]'), '');
    try {
      final response = await http.post(
        Uri.parse('https://restapi.easysendsms.app/v1/rest/sms/send'),
        headers: {
          'apikey': _easySendKey!,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'from': 'BrgySync',
          'to': digitsOnly,
          'text': message,
          'type': '0',
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['status'] == 'OK') {
          return null;
        }
        return 'EasySendSMS error: ${response.body}';
      } else {
        return 'EasySendSMS HTTP ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      return 'EasySendSMS network error: $e';
    }
  }

  /// Send via Twilio REST API.
  Future<String?> _sendTwilio(String to, String message) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$_twilioSid/Messages.json',
        ),
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$_twilioSid:$_twilioToken'))}',
        },
        body: {
          'From': _twilioFrom,
          'To': to,
          'Body': message,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return null;
      } else {
        // Silently handle trial account limitations
        try {
          final err = jsonDecode(response.body);
          if (err is Map &&
              (err['code'] == 21608 ||
                  err['code'] == 21612 ||
                  err['code'] == 21266)) {
            print('[Twilio] Trial limitation (code ${err['code']}): ${err['message']}');
            return null;
          }
        } catch (_) {}
        return 'Twilio error: ${response.statusCode} ${response.body}';
      }
    } catch (e) {
      return 'Twilio network error: $e';
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

  Future<String?> sendStatusAwaitingDocs(
      String mobile, String refNumber) async {
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
