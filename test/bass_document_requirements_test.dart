import 'package:brgysync_app/models/service_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final subType in [
    'Medical – Dialysis',
    'Medical – Chemotherapy',
    'Medical – Major Operations',
  ]) {
    test('$subType requires a Certificate of Admission upload', () {
      final certificate = kBassDocuments(
        subType,
      ).where((document) => document.name == 'Certificate of Admission');

      expect(certificate, hasLength(1));
      expect(certificate.single.required, isTrue);
      expect(certificate.single.uploaded, isFalse);
    });
  }

  test('non-medical BASS requests do not require admission certificate', () {
    final certificate = kBassDocuments(
      'Burial Assistance',
    ).where((document) => document.name == 'Certificate of Admission');

    expect(certificate, isEmpty);
  });

  test('medical assistance requests require a Medical Abstract', () {
    for (final subType in [
      'Medical – Dialysis',
      'Medical – Chemotherapy',
      'Medical – Major Operations',
    ]) {
      final names = kBassDocuments(subType).map((document) => document.name);
      expect(names, contains('Medical Abstract'));
      expect(names, isNot(contains('Death Certificate')));
      expect(names, isNot(contains("Doctor's Certificate")));
    }
  });

  test('burial assistance requires only the Death Certificate', () {
    final names = kBassDocuments(
      'Burial Assistance',
    ).map((document) => document.name);
    expect(names, contains('Death Certificate'));
    expect(names, isNot(contains('Medical Abstract')));
    expect(names, isNot(contains("Doctor's Certificate")));
  });

  test('drug rehabilitation requires only a Doctor\'s Certificate', () {
    final names = kBassDocuments(
      'Drug Rehabilitation',
    ).map((document) => document.name);
    expect(names, contains("Doctor's Certificate"));
    expect(names, isNot(contains('Medical Abstract')));
    expect(names, isNot(contains('Death Certificate')));
  });

  test('fire relief does not show unrelated medical evidence', () {
    final names = kBassDocuments(
      'Fire Relief',
    ).map((document) => document.name);
    expect(names, isNot(contains('Medical Abstract')));
    expect(names, isNot(contains("Doctor's Certificate")));
    expect(names, isNot(contains('Death Certificate')));
  });

  test(
    'relationship proof is conditional when requesting for someone else',
    () {
      final relationshipProof = kBassDocuments('Medical – Dialysis')
          .singleWhere(
            (document) =>
                document.name == 'Proof of relationship to patient / demised',
          );

      expect(relationshipProof.required, isFalse);
      expect(relationshipProof.requiredWhenRequestingForSomeoneElse, isTrue);

      relationshipProof.required =
          relationshipProof.requiredWhenRequestingForSomeoneElse;
      expect(relationshipProof.required, isTrue);
    },
  );
}
