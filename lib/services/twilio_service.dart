import 'dart:convert';
import 'package:http/http.dart' as http;

/// SMS service using MySMSGate as primary, EasySendSMS as fallback.
///
/// MySMSGate credentials injected at build time via --dart-define:
///   MYSMSGATE_API_KEY
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
  final String? _mySmsGateKey;
  final String? _easySendKey;
  final String? _twilioSid;
  final String? _twilioToken;
  final String? _twilioFrom;
  final bool _mockMode;

  TwilioService()
      : _mySmsGateKey = const String.fromEnvironment('MYSMSGATE_API_KEY'),
        _easySendKey = const String.fromEnvironment('EASYSENDSMS_API_KEY'),
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

  /// Send an SMS. Tries MySMSGate first, then EasySendSMS, then Twilio.
  /// Returns null on success, error message on failure.
  Future<String?> sendSms(String toNumber, String message) async {
    final to = formatPhoneNumber(toNumber);
    print('[SMS] sendSms called — to: $to, message: $message');
    print('[SMS] _mySmsGateKey: ${_mySmsGateKey != null && _mySmsGateKey!.isNotEmpty ? "SET" : "EMPTY"}');
    print('[SMS] _easySendKey: ${_easySendKey != null && _easySendKey!.isNotEmpty ? "SET" : "EMPTY"}');
    print('[SMS] _twilioSid: ${_twilioSid != null && _twilioToken != null && _twilioFrom != null ? "SET" : "EMPTY"}');

    if (_mockMode) {
      print('[MOCK SMS] To: $to | Message: $message');
      return null;
    }

    // ── Primary: MySMSGate (Android SMS Gateway) ──
    if (_mySmsGateKey != null && _mySmsGateKey!.isNotEmpty) {
      print('[SMS] Trying MySMSGate...');
      final result = await _sendMySMSGate(to, message);
      print('[SMS] MySMSGate result: $result');
      if (result == null) return null;
    }

    // ── Fallback 1: EasySendSMS ──
    if (_easySendKey != null && _easySendKey!.isNotEmpty) {
      print('[SMS] Trying EasySendSMS...');
      final result = await _sendEasySend(to, message);
      print('[SMS] EasySendSMS result: $result');
      if (result == null) return null;
    }

    // ── Fallback 2: Twilio ──
    if (_twilioSid != null && _twilioToken != null && _twilioFrom != null) {
      print('[SMS] Trying Twilio...');
      return _sendTwilio(to, message);
    }

    print('[SMS] No provider configured');
    return 'No SMS provider configured.';
  }

  /// Send via MySMSGate through Cloudflare Worker proxy (avoids CORS).
  Future<String?> _sendMySMSGate(String to, String message) async {
    try {
      final response = await http.post(
        Uri.parse('https://sms-proxy.brgy-sync.workers.dev/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': to,
          'message': message,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        final body = jsonDecode(response.body);
        if (body['success'] != false) return null;
        return 'MySMSGate error: ${response.body}';
      } else if (response.statusCode == 402) {
        return 'MySMSGate: Insufficient SMS balance.';
      } else {
        return 'MySMSGate HTTP ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      return 'MySMSGate network error: $e';
    }
  }

  /// Send via EasySendSMS REST API.
  Future<String?> _sendEasySend(String to, String message) async {
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
          'from': 'BRGYSYNC',
          'to': digitsOnly,
          'text': message,
          'type': '0',
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['status'] == 'OK') return null;
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
        try {
          final err = jsonDecode(response.body);
          if (err is Map &&
              (err['code'] == 21608 ||
                  err['code'] == 21612 ||
                  err['code'] == 21266)) {
            return null; // silently handle trial limitations
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
