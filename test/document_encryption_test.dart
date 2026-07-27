import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('document bytes survive encrypted Realtime Database encoding', () async {
    final algorithm = AesGcm.with256bits();
    final original = utf8.encode('sample resident document');
    final key = await algorithm.newSecretKey();
    final encrypted = await algorithm.encrypt(original, secretKey: key);

    final storedCipherText = base64Encode(encrypted.cipherText);
    final storedNonce = base64Encode(encrypted.nonce);
    final storedMac = base64Encode(encrypted.mac.bytes);

    final restored = await algorithm.decrypt(
      SecretBox(
        base64Decode(storedCipherText),
        nonce: base64Decode(storedNonce),
        mac: Mac(base64Decode(storedMac)),
      ),
      secretKey: key,
    );

    expect(restored, original);
  });
}
