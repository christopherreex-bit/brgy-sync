import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class FinancialSlipOcrService {
  static const proxyUrl = String.fromEnvironment(
    'FINANCIAL_OCR_PROXY_URL',
    defaultValue:
        'https://brgy-sync-financial-slip-ocr.jasonleyva723.workers.dev',
  );

  Future<FinancialSlipOcrResult> extract({
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (proxyUrl.isEmpty) {
      throw StateError('Financial-slip OCR is not configured.');
    }
    if (contentType != 'image/jpeg' && contentType != 'image/png') {
      throw StateError('Automatic extraction supports JPG and PNG slips.');
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in again before scanning a financial slip.');
    }
    final response = await http
        .post(
          Uri.parse(proxyUrl).replace(path: '/extract'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'image': base64Encode(bytes),
            'contentType': contentType,
          }),
        )
        .timeout(const Duration(seconds: 35));
    final decoded = response.body.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        (decoded['error'] ?? 'Could not read the uploaded slip.').toString(),
      );
    }
    return FinancialSlipOcrResult.fromMap(
      Map<String, dynamic>.from(decoded['result'] as Map? ?? const {}),
    );
  }
}

class FinancialSlipOcrResult {
  final double? amount;
  final String transactionNumber;
  final String transactionDate;
  final String financialInstitution;
  final double confidence;
  final String rawText;

  const FinancialSlipOcrResult({
    required this.amount,
    required this.transactionNumber,
    required this.transactionDate,
    required this.financialInstitution,
    required this.confidence,
    required this.rawText,
  });

  factory FinancialSlipOcrResult.fromMap(Map<String, dynamic> map) {
    final rawAmount = map['amount'];
    return FinancialSlipOcrResult(
      amount: rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse(
              rawAmount?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '',
            ),
      transactionNumber: (map['transactionNumber'] ?? '').toString().trim(),
      transactionDate: (map['transactionDate'] ?? '').toString().trim(),
      financialInstitution: (map['financialInstitution'] ?? '')
          .toString()
          .trim(),
      confidence: (map['confidence'] as num?)?.toDouble().clamp(0, 1) ?? 0,
      rawText: (map['rawText'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {
    if (amount != null) 'amount': amount,
    'transactionNumber': transactionNumber,
    'transactionDate': transactionDate,
    'financialInstitution': financialInstitution,
    'confidence': confidence,
    'rawText': rawText,
  };
}

class FinancialEvidenceDraft {
  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final FinancialSlipOcrResult? ocrResult;

  const FinancialEvidenceDraft({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    this.ocrResult,
  });
}
