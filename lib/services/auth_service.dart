import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hex/hex.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;

class AuthService {
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Uint8List? _fullPrivateKeyBytes;

  // --- RFC8032 TEST VECTOR SEED (32 bytes) ---
  static const String _seedHex =
      "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60";

  // --- RFC8032 PUBLIC KEY (32 bytes) ---
  static const String _publicKeyHex =
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a";

  // --- EXPANDED PRIVATE KEY (seed + public key = 64 bytes) ---
  static const String _fullPrivateKeyHex =
      "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a";

  final String _provisioningStatusKey = "provisioning_complete";

  // ------------------------------------------------------------------
  // BACKWARD COMPATIBILITY
  // ------------------------------------------------------------------
  Future<void> ensureKeyPair() async => ensureKeys();
  String? getProvisioningPublicKey() => _publicKeyHex;
  String get publicKey => _publicKeyHex;

  // ------------------------------------------------------------------
  // LOAD KEYPAIR ONCE
  // ------------------------------------------------------------------
  Future<void> ensureKeys() async {
    if (_fullPrivateKeyBytes != null) return;

    _fullPrivateKeyBytes = Uint8List.fromList(HEX.decode(_fullPrivateKeyHex));

    debugPrint("🔐 Ed25519 PRIVATE KEY (EXPANDED, 64 bytes)");
    debugPrint("🔐 First 16 hex of private key: ${_fullPrivateKeyHex.substring(0, 16)}...");
    debugPrint("🔐 Public key loaded: $_publicKeyHex");
  }

  // ------------------------------------------------------------------
  // NORMALIZE NONCE
  // ------------------------------------------------------------------
  String normalizeNonce(String nonce) {
    var n = nonce.trim();
    if (n.startsWith("0x") || n.startsWith("0X")) n = n.substring(2);
    return n.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  }

  // ------------------------------------------------------------------
  // SIGN VP PAYLOAD using Ed25519ph (SHA-512 Pre-hash MODE)
  // ------------------------------------------------------------------
  Future<String> signChallengeAndBuildVpJson({required String nonce}) async {
    await ensureKeys();

    final clean = normalizeNonce(nonce);
    const vc = "valid_access";
    final message = "$clean|$vc";

    final msgBytes = Uint8List.fromList(utf8.encode(message));
    debugPrint("📝 Signing message: '$message'");
    debugPrint("📝 Msg hex: ${HEX.encode(msgBytes)}");

    // SHA-512 digest → 64 bytes
    final digest = crypto.sha512.convert(msgBytes).bytes;
    debugPrint("🔐 SHA512 digest hex: ${HEX.encode(digest)}");

    // SIGN SHA-512 digest (Ed25519-ph)
    final privateKey = ed25519.PrivateKey(_fullPrivateKeyBytes!);
    final signature = ed25519.sign(privateKey, Uint8List.fromList(digest));
    final signatureHex = HEX.encode(signature);

    debugPrint("✒ Signature hex [64 bytes]: $signatureHex");
    debugPrint("🔏 Mode: Ed25519ph (pre-hashed)");

    return jsonEncode({
      "nonce": clean,
      "vc": vc,
      "signature_hex": signatureHex,
    });
  }

  // ------------------------------------------------------------------
  // OPTIONAL BIOMETRIC
  // ------------------------------------------------------------------
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: "Tap fingerprint to unlock",
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (e) {
      debugPrint("Auth Error: $e");
      return false;
    }
  }

  Future<bool> isProvisioningComplete() async {
    final status = await _secureStorage.read(key: _provisioningStatusKey);
    return status == "true";
  }

  Future<void> setProvisioningComplete(bool complete) async {
    await _secureStorage.write(
      key: _provisioningStatusKey,
      value: complete ? "true" : "false",
    );
  }
}