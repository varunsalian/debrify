import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as cr;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;

class PasteShDecryptor {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko)';

  static Future<String> decrypt(String urlWithHash) async {
    final hashIdx = urlWithHash.indexOf('#');
    if (hashIdx <= 0) return '';
    final baseUrl = urlWithHash.substring(0, hashIdx);
    final clientKey = urlWithHash.substring(hashIdx + 1);
    final id = baseUrl.substring(baseUrl.lastIndexOf('/') + 1);

    final raw = await _httpGetText('$baseUrl.txt');
    if (raw == null || raw.isEmpty) return '';
    final lines = raw.split('\n');
    if (lines.isEmpty) return '';
    final serverKey = lines.first.trim();
    final b64 = lines.skip(1).join().trim();
    if (b64.isEmpty) return '';

    Uint8List cipherBytes;
    try {
      cipherBytes = base64.decode(b64);
    } catch (_) {
      return '';
    }
    if (cipherBytes.length < 17) return '';

    final salt = cipherBytes.sublist(8, 16);
    final ct = cipherBytes.sublist(16);
    final password = '$id$serverKey$clientKey' 'https://paste.sh';
    final passBytes = utf8.encode(password);

    try {
      final keyIv = _pbkdf2HmacSha512(passBytes, salt, 1, 48);
      final key = keyIv.sublist(0, 32);
      final iv = keyIv.sublist(32, 48);
      final out = _aesCbcDecrypt(ct, key, iv);
      if (out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('Decrypt PBKDF2 path failed: $e');
    }

    try {
      final pair = _evpBytesToKey(passBytes, salt, 32, 16);
      final out = _aesCbcDecrypt(ct, pair.$1, pair.$2);
      if (out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('Decrypt EVP path failed: $e');
    }

    return '';
  }

  static String _aesCbcDecrypt(
      Uint8List ct, Uint8List key, Uint8List iv) {
    final params = pc.PaddedBlockCipherParameters<pc.ParametersWithIV<pc.KeyParameter>, Null>(
      pc.ParametersWithIV(pc.KeyParameter(key), iv),
      null,
    );
    final cipher = pc.PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(false, params);
    final out = cipher.process(ct);
    return utf8.decode(out, allowMalformed: true);
  }

  static Uint8List _pbkdf2HmacSha512(
      Uint8List password, Uint8List salt, int iterations, int dkLen) {
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA512Digest(), 128))
      ..init(pc.Pbkdf2Parameters(salt, iterations, dkLen));
    return pbkdf2.process(password);
  }

  static (Uint8List, Uint8List) _evpBytesToKey(
      Uint8List password, Uint8List salt, int keyLen, int ivLen) {
    final out = BytesBuilder();
    var prev = const <int>[];
    while (out.length < keyLen + ivLen) {
      final input = <int>[
        ...prev,
        ...password,
        ...salt,
      ];
      prev = cr.md5.convert(input).bytes;
      out.add(prev);
    }
    final all = out.toBytes();
    return (
      Uint8List.fromList(all.sublist(0, keyLen)),
      Uint8List.fromList(all.sublist(keyLen, keyLen + ivLen)),
    );
  }

  static Future<String?> _httpGetText(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return resp.body;
    } catch (e) {
      debugPrint('Decrypt GET failed: $e');
      return null;
    }
  }
}
