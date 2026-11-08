import 'package:brgysync_app/services/financial_slip_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses editable financial slip fields from OCR response', () {
    final result = FinancialSlipOcrResult.fromMap({
      'amount': '₱ 12,500.00',
      'transactionNumber': 'TRX-00491',
      'transactionDate': '2026-11-08',
      'financialInstitution': 'Sample Bank',
      'confidence': 0.87,
      'rawText': 'Amount 12,500.00 Ref TRX-00491',
    });

    expect(result.amount, 12500);
    expect(result.transactionNumber, 'TRX-00491');
    expect(result.transactionDate, '2026-11-08');
    expect(result.financialInstitution, 'Sample Bank');
    expect(result.confidence, 0.87);
  });

  test('clamps invalid OCR confidence and leaves unreadable amount null', () {
    final result = FinancialSlipOcrResult.fromMap({
      'amount': null,
      'confidence': 4,
    });

    expect(result.amount, isNull);
    expect(result.confidence, 1);
  });
}
