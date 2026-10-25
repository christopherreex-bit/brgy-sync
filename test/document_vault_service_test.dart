import 'package:brgysync_app/services/document_vault_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system-generated indigency certificates are reusable for 60 days', () {
    expect(
      DocumentVaultService.validityDays('Barangay Certificate of Indigency'),
      60,
    );
  });

  test('case-specific medical evidence remains non-reusable', () {
    expect(DocumentVaultService.validityDays('Certificate of Admission'), null);
    expect(
      DocumentVaultService.validityDays(
        "Medical Abstract / Doctor's Certificate",
      ),
      null,
    );
  });
}
