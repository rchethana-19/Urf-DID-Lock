// Paste into a debug file or call from your UI
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';
import 'package:flutter/foundation.dart';

/// Returns a map describing verification results
Future<Map<String, dynamic>> verifyVpLocally({
  required String nonce,
  required String vc,
  required String signatureHex,
  required String publicKeyHex,
}) async {
  final cleanNonce = nonce.trim().replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  final msg = '$cleanNonce|$vc';
  final msgBytes = utf8.encode(msg);
  final sig = Uint8List.fromList(HEX.decode(signatureHex));
  final pub = Uint8List.fromList(HEX.decode(publicKeyHex));

  debugPrint('Local verify: message="$msg"');
  debugPrint('Msg bytes (hex): ${HEX.encode(Uint8List.fromList(msgBytes))}');
  debugPrint('Signature hex: $signatureHex');
  debugPrint('Public key hex: $publicKeyHex');

  if (sig.length != 64) {
    return {'ok': false, 'reason': 'signature length not 64', 'raw_ok': false, 'prehash_ok': false};
  }
  if (pub.length != 32) {
    return {'ok': false, 'reason': 'public key length not 32', 'raw_ok': false, 'prehash_ok': false};
  }

  // Build PublicKey for ed25519_edwards
  final publicKey = ed.PublicKey(pub);

  // 1) Pure Ed25519 verification (message signed directly)
  bool rawOk = false;
  try {
    rawOk = ed.verify(publicKey, Uint8List.fromList(msgBytes), sig);
  } catch (e) {
    debugPrint('raw verify exception: $e');
  }

  // 2) Pre-hash mode (Ed25519ph): verify(signature, SHA512(message))
  bool prehashOk = false;
  try {
    final digest = crypto.sha512.convert(msgBytes).bytes; // 64 bytes
    prehashOk = ed.verify(publicKey, Uint8List.fromList(digest), sig);
  } catch (e) {
    debugPrint('prehash verify exception: $e');
  }

  final ok = rawOk || prehashOk;
  return {
    'ok': ok,
    'raw_ok': rawOk,
    'prehash_ok': prehashOk,
    'message': msg,
  };
}