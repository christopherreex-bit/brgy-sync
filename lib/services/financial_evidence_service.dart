import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:firebase_database/firebase_database.dart';

import 'financial_slip_ocr_service.dart';

class FinancialEvidenceService {
  final FirebaseDatabase _database;
  final AesGcm _encryption = AesGcm.with256bits();

  FinancialEvidenceService({FirebaseDatabase? database})
    : _database = database ?? FirebaseDatabase.instance;

  Future<Map<String, dynamic>> upload({
    required String ownerId,
    required String movementId,
    required FinancialEvidenceDraft draft,
  }) async {
    final path = 'financialDocuments/$ownerId/$movementId/slip';
    final secretKey = await _encryption.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    final encrypted = await _encryption.encrypt(
      draft.bytes,
      secretKey: secretKey,
    );
    await _database.ref(path).set({
      'ownerId': ownerId,
      'cipherText': base64Encode(encrypted.cipherText),
      'nonce': base64Encode(encrypted.nonce),
      'mac': base64Encode(encrypted.mac.bytes),
      'contentType': draft.contentType,
      'size': draft.bytes.length,
    });
    return {
      'fileName': draft.fileName,
      'contentType': draft.contentType,
      'size': draft.bytes.length,
      'databasePath': path,
      'encryptionKey': base64Encode(keyBytes),
      'uploadedBy': ownerId,
    };
  }

  Future<void> delete(String databasePath) async {
    if (databasePath.isEmpty) return;
    await _database.ref(databasePath).remove();
  }

  Future<FinancialEvidenceFile> download(Map<String, dynamic> metadata) async {
    final path = (metadata['databasePath'] ?? '').toString();
    final encodedKey = (metadata['encryptionKey'] ?? '').toString();
    if (path.isEmpty || encodedKey.isEmpty) {
      throw StateError('The financial evidence has no downloadable file.');
    }
    final snapshot = await _database.ref(path).get();
    if (!snapshot.exists || snapshot.value is! Map) {
      throw StateError('The financial evidence could not be found.');
    }
    final raw = Map<Object?, Object?>.from(snapshot.value as Map);
    final encrypted = SecretBox(
      base64Decode(raw['cipherText'].toString()),
      nonce: base64Decode(raw['nonce'].toString()),
      mac: Mac(base64Decode(raw['mac'].toString())),
    );
    final clearBytes = await _encryption.decrypt(
      encrypted,
      secretKey: SecretKey(base64Decode(encodedKey)),
    );
    return FinancialEvidenceFile(
      bytes: Uint8List.fromList(clearBytes),
      contentType: (metadata['contentType'] ?? raw['contentType'] ?? '')
          .toString(),
      fileName: (metadata['fileName'] ?? 'financial-slip').toString(),
    );
  }
}

class FinancialEvidenceFile {
  final Uint8List bytes;
  final String contentType;
  final String fileName;

  const FinancialEvidenceFile({
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });
}
