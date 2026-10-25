import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import 'document_vault_service.dart';

class IndigencyCertificateService {
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;
  final _encryption = AesGcm.with256bits();

  IndigencyCertificateService({
    FirebaseFirestore? firestore,
    FirebaseDatabase? database,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _database = database ?? FirebaseDatabase.instance;

  Future<void> generateAndStore({
    required String registryId,
    required Map<String, dynamic> citizen,
    required UserModel actor,
    required String reason,
  }) async {
    if (citizen['verificationStatus'] != 'verified') {
      throw StateError(
        'The citizen record must be verified before a certificate can be generated.',
      );
    }
    final name = (citizen['legalName'] ?? '').toString().trim();
    final address = (citizen['permanentAddress'] ?? '').toString().trim();
    if (name.isEmpty || address.isEmpty) {
      throw StateError('The verified record must contain a name and address.');
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Enter the reason for issuing the certificate.');
    }

    final issuedAt = DateTime.now();
    final validUntil = issuedAt.add(const Duration(days: 60));
    final certificateNumber = await _nextCertificateNumber(issuedAt.year);
    final signatories = await _resolveSignatories();
    final bytes = await _buildPdf(
      certificateNumber: certificateNumber,
      name: name,
      address: address,
      reason: trimmedReason,
      issuedAt: issuedAt,
      validUntil: validUntil,
      captainName: signatories.captain,
      secretaryName: signatories.secretary,
    );
    final key = await _encryption.newSecretKey();
    final keyBytes = await key.extractBytes();
    final encrypted = await _encryption.encrypt(bytes, secretKey: key);
    final documentId = DocumentVaultService.documentKey(
      'Barangay Certificate of Indigency',
    );
    final storageId = const Uuid().v4();
    final databasePath =
        'caseDocuments/${actor.uid}/registry_$registryId/$storageId';

    await _database.ref(databasePath).set({
      'ownerId': actor.uid,
      'cipherText': base64Encode(encrypted.cipherText),
      'nonce': base64Encode(encrypted.nonce),
      'mac': base64Encode(encrypted.mac.bytes),
      'contentType': 'application/pdf',
      'size': bytes.length,
    });

    try {
      await _firestore
          .collection('citizenRegistry')
          .doc(registryId)
          .collection('verifiedDocuments')
          .doc(documentId)
          .set({
            'name': 'Barangay Certificate of Indigency',
            'status': 'verified',
            'verificationStatus': 'verified',
            'fileName': '$certificateNumber.pdf',
            'contentType': 'application/pdf',
            'size': bytes.length,
            'databasePath': databasePath,
            'encryptionKey': base64Encode(keyBytes),
            'certificateNumber': certificateNumber,
            'reason': trimmedReason,
            'issuedAt': Timestamp.fromDate(issuedAt),
            'validUntil': Timestamp.fromDate(validUntil),
            'generatedAt': FieldValue.serverTimestamp(),
            'generatedBy': actor.uid,
            'generatedByName': actor.name,
            'generatedByRole': actor.role,
            'captainSignatoryName': signatories.captain,
            'secretarySignatoryName': signatories.secretary,
            'verifiedAt': FieldValue.serverTimestamp(),
            'verifiedBy': actor.uid,
            'verifiedByName': actor.name,
            'source': 'system_generated',
          }, SetOptions(merge: true));
    } catch (_) {
      await _database.ref(databasePath).remove();
      rethrow;
    }

    await Printing.layoutPdf(
      name: '$certificateNumber.pdf',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> previewStored(Map<String, dynamic> document) async {
    final path = (document['databasePath'] ?? '').toString();
    final encodedKey = (document['encryptionKey'] ?? '').toString();
    if (path.isEmpty || encodedKey.isEmpty) {
      throw StateError('The stored certificate file is unavailable.');
    }
    final snapshot = await _database.ref(path).get();
    if (!snapshot.exists || snapshot.value is! Map) {
      throw StateError('The stored certificate file could not be found.');
    }
    final stored = Map<String, dynamic>.from(snapshot.value! as Map);
    final clearBytes = await _encryption.decrypt(
      SecretBox(
        base64Decode((stored['cipherText'] ?? '').toString()),
        nonce: base64Decode((stored['nonce'] ?? '').toString()),
        mac: Mac(base64Decode((stored['mac'] ?? '').toString())),
      ),
      secretKey: SecretKey(base64Decode(encodedKey)),
    );
    await Printing.layoutPdf(
      name: (document['fileName'] ?? 'certificate-of-indigency.pdf').toString(),
      onLayout: (_) async => Uint8List.fromList(clearBytes),
    );
  }

  Future<String> _nextCertificateNumber(int year) async {
    final counterRef = _firestore
        .collection('certificateCounters')
        .doc('$year');
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);
      final next = ((snapshot.data()?['lastNumber'] as num?)?.toInt() ?? 0) + 1;
      transaction.set(counterRef, {
        'lastNumber': next,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return 'IND-$year-${next.toString().padLeft(5, '0')}';
    });
  }

  Future<({String captain, String secretary})> _resolveSignatories() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', whereIn: ['captain', 'officer'])
        .get();
    final accounts = snapshot.docs
        .map((document) => document.data())
        .where((data) => data['isActive'] != false)
        .toList();
    String accountName(String role, String fallback) {
      final matches = accounts.where((data) => data['role'] == role).toList()
        ..sort(
          (a, b) => (a['name'] ?? '').toString().compareTo(
            (b['name'] ?? '').toString(),
          ),
        );
      if (matches.isEmpty) return fallback;
      final name = (matches.first['name'] ?? '').toString().trim();
      return name.isEmpty ? fallback : name;
    }

    return (
      captain: accountName('captain', 'Barangay Captain'),
      secretary: accountName('officer', 'Barangay Secretary'),
    );
  }

  Future<Uint8List> _buildPdf({
    required String certificateNumber,
    required String name,
    required String address,
    required String reason,
    required DateTime issuedAt,
    required DateTime validUntil,
    required String captainName,
    required String secretaryName,
  }) async {
    final pdf = pw.Document();
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final italicFont = await PdfGoogleFonts.notoSansItalic();
    final boldItalicFont = await PdfGoogleFonts.notoSansBoldItalic();
    final issueDate = DateFormat('d MMMM yyyy').format(issuedAt);
    final expiryDate = DateFormat('d MMMM yyyy').format(validUntil);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(64, 45, 64, 55),
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
          italic: italicFont,
          boldItalic: boldItalicFont,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'Republic of the Philippines',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                  pw.Text(
                    'OFFICE OF THE BARANGAY COUNCIL',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Barangay Calzada-Tipas',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                  pw.Text('City of Taguig'),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Certificate No. $certificateNumber',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 62),
            pw.Center(
              child: pw.Text(
                'CERTIFICATE OF INDIGENCY',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 68),
            pw.Text(
              'TO WHOM IT MAY CONCERN:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 30),
            pw.RichText(
              textAlign: pw.TextAlign.justify,
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 5),
                children: [
                  const pw.TextSpan(text: 'This is to certify that '),
                  pw.TextSpan(
                    text: name.toUpperCase(),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  const pw.TextSpan(
                    text:
                        ' is a bona fide resident of this barangay with postal address at ',
                  ),
                  pw.TextSpan(
                    text: address,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  const pw.TextSpan(text: '.'),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Paragraph(
              text:
                  'This further certifies that the above-mentioned person is one of the indigent residents of this barangay whose family income is barely enough to sustain everyday needs.',
              textAlign: pw.TextAlign.justify,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 5),
            ),
            pw.RichText(
              textAlign: pw.TextAlign.justify,
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 5),
                children: [
                  const pw.TextSpan(
                    text:
                        'This certification is hereby issued upon request to avail ',
                  ),
                  pw.TextSpan(text: reason),
                  const pw.TextSpan(text: '.'),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 12),
                children: [
                  const pw.TextSpan(text: 'Issued this '),
                  pw.TextSpan(
                    text: issueDate,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  const pw.TextSpan(text: ' at '),
                  pw.TextSpan(
                    text: 'Barangay Calzada-Tipas, Taguig City',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  const pw.TextSpan(text: '.'),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Valid for 60 days from date of issuance\nValid until $expiryDate',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _signatureLine('Approved by:', captainName, 'Barangay Captain'),
                _signatureLine(
                  'Attested by:',
                  secretaryName,
                  'Barangay Secretary',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  pw.Widget _signatureLine(String heading, String name, String position) {
    return pw.SizedBox(
      width: 180,
      child: pw.Column(
        children: [
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(heading, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            '/s/ ${name.toUpperCase()}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 4),
          pw.Container(height: 1, color: PdfColors.black),
          pw.SizedBox(height: 3),
          pw.Text(
            name.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(position, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            'Electronic signature',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }
}
