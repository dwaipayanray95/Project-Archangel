import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// PIN-derived encryption for data that shouldn't depend on the OS
/// Keychain/Credential Manager at all - used for the saved SSH private
/// key (see ssh_credentials.dart) instead of flutter_secure_storage.
///
/// Why: flutter_secure_storage on macOS is a thin wrapper over Keychain
/// Services, which gates every read/write behind the app's code-signing
/// identity via the Keychain Sharing entitlement. Without a stable
/// entitlement (which requires Xcode to set up), every dev rebuild gets
/// re-signed differently and macOS treats it as a new app, re-prompting
/// for Keychain access on every field. Deriving our own key from a PIN
/// the user chooses sidesteps that dependency entirely, works
/// identically on every platform (no OS-specific secure-storage backend
/// to get right), and - unlike a hardcoded/app-embedded key, which would
/// just be obfuscation - is real encryption: the ciphertext is
/// unrecoverable without a PIN only the user knows, which also means it
/// scales to multiple users of the same install, each with their own PIN.
///
/// The PIN itself is never stored anywhere - only its effect (the
/// derived key) is, transiently, in memory for as long as it takes to
/// encrypt/decrypt.
class WrongPinException implements Exception {
  const WrongPinException();
  @override
  String toString() => 'Incorrect PIN, or the saved data is corrupted.';
}

class _Envelope {
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;
  const _Envelope({required this.salt, required this.nonce, required this.cipherText, required this.mac});

  Uint8List encode() {
    final map = {
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipherText': base64Encode(cipherText),
      'mac': base64Encode(mac),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  static _Envelope decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return _Envelope(
      salt: base64Decode(map['salt'] as String),
      nonce: base64Decode(map['nonce'] as String),
      cipherText: base64Decode(map['cipherText'] as String),
      mac: base64Decode(map['mac'] as String),
    );
  }
}

const _pbkdf2Iterations = 200000; // ~100-300ms on typical hardware
const _keyBits = 256;

final _pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _pbkdf2Iterations, bits: _keyBits);
final _aesGcm = AesGcm.with256bits();

Future<SecretKey> _deriveKey(String pin, List<int> salt) {
  return _pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
}

/// Encrypts [plaintextJson] (any JSON-encodable map) under a key derived
/// from [pin], returning the bytes to write to disk. A fresh random salt
/// and nonce are generated every call - safe to call repeatedly with the
/// same PIN.
Future<Uint8List> encryptJson(String pin, Map<String, dynamic> plaintextJson) async {
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
  final secretKey = await _deriveKey(pin, salt);
  final plaintext = utf8.encode(jsonEncode(plaintextJson));
  final box = await _aesGcm.encrypt(plaintext, secretKey: secretKey);
  return _Envelope(
    salt: salt,
    nonce: Uint8List.fromList(box.nonce),
    cipherText: Uint8List.fromList(box.cipherText),
    mac: Uint8List.fromList(box.mac.bytes),
  ).encode();
}

/// Reverses [encryptJson]. Throws [WrongPinException] if [pin] is wrong
/// or [envelopeBytes] has been tampered with/corrupted - AES-GCM's
/// authentication tag makes the two indistinguishable, which is
/// intentional (don't leak which one it was).
Future<Map<String, dynamic>> decryptJson(String pin, Uint8List envelopeBytes) async {
  try {
    final envelope = _Envelope.decode(envelopeBytes);
    final secretKey = await _deriveKey(pin, envelope.salt);
    final box = SecretBox(envelope.cipherText, nonce: envelope.nonce, mac: Mac(envelope.mac));
    final plaintext = await _aesGcm.decrypt(box, secretKey: secretKey);
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  } catch (_) {
    throw const WrongPinException();
  }
}
