import 'package:flutter_test/flutter_test.dart';
import 'package:brgysync_app/utils/rejection_reasons.dart';

void main() {
  test('standard rejection reasons have stable analytics codes', () {
    expect(rejectionReasonLabels['ineligible'], isNotEmpty);
    expect(rejectionReasonLabels['insufficient_funds'], isNotEmpty);
    expect(rejectionReasonLabels['not_resident'], isNotEmpty);
    expect(rejectionReasonLabels['other'], isNotEmpty);
  });

  test('unknown historical codes receive a readable label', () {
    expect(rejectionReasonLabel('old_reason'), 'Unspecified legacy reason');
  });
}
