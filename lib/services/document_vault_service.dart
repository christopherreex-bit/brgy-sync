import 'package:cloud_firestore/cloud_firestore.dart';

/// Rules and lookups for documents that may safely be reused in later cases.
class DocumentVaultService {
  final FirebaseFirestore _db;

  DocumentVaultService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  static String documentKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  /// Conservative validity periods. Case-specific medical and financial
  /// evidence is deliberately excluded and must be uploaded for every case.
  static int? validityDays(String name) {
    final normalized = name.toLowerCase();
    if (normalized.startsWith('valid id')) return 365;
    if (normalized.contains("voter's certificate")) return 1095;
    if (normalized.contains('proof of relationship')) return 1095;
    return null;
  }

  static bool isReusable(String name) => validityDays(name) != null;

  Future<Map<String, Map<String, dynamic>>> validDocumentsForRegistry(
    String registryId,
  ) async {
    if (registryId.isEmpty) return const {};
    final snapshot = await _db
        .collection('citizenRegistry')
        .doc(registryId)
        .collection('verifiedDocuments')
        .get();
    final now = DateTime.now();
    final result = <String, Map<String, dynamic>>{};
    for (final document in snapshot.docs) {
      final data = document.data();
      if (data['verificationStatus'] != 'verified') continue;
      final validUntil = data['validUntil'];
      if (validUntil is Timestamp && validUntil.toDate().isBefore(now)) {
        continue;
      }
      final name = (data['name'] ?? '').toString();
      if (name.isEmpty || !isReusable(name)) continue;
      result[document.id] = {...data, 'vaultDocumentId': document.id};
    }
    return result;
  }
}
