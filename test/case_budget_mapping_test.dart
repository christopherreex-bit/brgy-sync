import 'package:brgysync_app/services/case_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps BASS case subtypes to their budget programs', () {
    expect(
      budgetProgramNameForCase('bass', 'Medical – Dialysis'),
      'BASS – Medical Assistance',
    );
    expect(
      budgetProgramNameForCase('bass', 'Medical – Chemotherapy'),
      'BASS – Medical Assistance',
    );
    expect(
      budgetProgramNameForCase('bass', 'Medical – Major Operations'),
      'BASS – Medical Assistance',
    );
    expect(
      budgetProgramNameForCase('bass', 'Burial Assistance'),
      'BASS – Burial Assistance',
    );
    expect(
      budgetProgramNameForCase('bass', 'Drug Rehabilitation'),
      'BASS – Drug Rehabilitation',
    );
    expect(
      budgetProgramNameForCase('bass', 'Fire Relief'),
      'BASS – Fire Relief',
    );
  });

  test('birthday registration programs have no budget mapping', () {
    expect(
      budgetProgramNameForCase(
        'beneficiary',
        'Senior Citizen Birthday Program',
      ),
      isNull,
    );
    expect(
      budgetProgramNameForCase('beneficiary', 'PWD Birthday Program'),
      isNull,
    );
  });

  test('derives the calendar quarter from the release date', () {
    expect(quarterForDate(DateTime(2026, 1, 1)), 1);
    expect(quarterForDate(DateTime(2026, 4, 1)), 2);
    expect(quarterForDate(DateTime(2026, 7, 27)), 3);
    expect(quarterForDate(DateTime(2026, 12, 31)), 4);
  });

  test('Education Incentive uses its approved assistance amount', () {
    expect(
      budgetDeductionAmountForCase({
        'serviceCategory': 'education',
        'serviceSubType': 'Honor Student Application',
        'assistanceAmount': 750,
      }),
      750,
    );
  });

  test('BASS requests use their entered assistance amount', () {
    expect(
      budgetDeductionAmountForCase({
        'serviceCategory': 'bass',
        'serviceSubType': 'Burial Assistance',
        'assistanceAmount': 1250,
      }),
      1250,
    );
  });
}
