import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_util.dart';

/// AES-GCM-256 encryption-at-rest for credential strings in SharedPreferences.
///
/// Obfuscation-grade by design: the master key is HKDF(pepper ∥ device-ID),
/// where the pepper ships inside the app binary. An attacker with both the
/// binary and the device ID can derive the key; the goal is defeating
/// plaintext reads of the prefs file (rooted boxes, backup scrapes, desktop
/// file access) and binding ciphertext to the device it was written on — not
/// resisting a targeted attacker running code on that device. The app ships
/// unsigned, so OS keystores (which require entitlements) are unavailable.
///
/// Value format: `enc1:` + base64(nonce(12) ∥ ciphertext ∥ tag(16)).
/// A stored value with the prefix is ALWAYS treated as ciphertext — there is
/// deliberately no plaintext fallback on decrypt failure, since that would
/// turn tampering into injection. A legacy plaintext value that happens to
/// start with `enc1:` therefore reads as null once; accepted (no real
/// credential shape collides with the prefix).
class SecretVault {
  SecretVault._();

  static const String prefix = 'enc1:';
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  // Compiled into the binary. Its job is making the derived key non-obvious,
  // not being secret from someone who reverse-engineers the app.
  static const List<int> _pepper = [
    3, 199, 32, 163, 35, 25, 9, 245, 14, 252, 204, 172, 74, 64, 180, 94, //
    230, 248, 87, 4, 175, 59, 151, 150, 220, 197, 5, 82, 68, 33, 150, 113,
  ];
  static const List<int> _hkdfSalt = [
    19, 126, 161, 133, 65, 154, 196, 229, 237, 165, 172, 17, 159, 44, 23, 89, //
    3, 97, 230, 120, 123, 166, 77, 99, 32, 16, 242, 6, 138, 236, 242, 239,
  ];

  static final AesGcm _aes = AesGcm.with256bits();

  static Future<SecretKey>? _keyFuture;
  static bool _deviceIdOverridden = false;
  static String? _deviceIdOverride;

  // ---------------------------------------------------------------- core ---

  /// Encrypts [plaintext] into the `enc1:` envelope.
  static Future<String> seal(String plaintext) async {
    final key = await _key();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    final packed = <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
    return '$prefix${base64Encode(packed)}';
  }

  /// Decrypts a stored value.
  ///
  /// null → null. `enc1:`-prefixed → decrypt; ANY failure → null (caller
  /// treats the credential as absent/signed-out). Anything else is legacy
  /// plaintext and is returned verbatim.
  static Future<String?> open(String? stored) async {
    if (stored == null) return null;
    if (!stored.startsWith(prefix)) return stored;
    try {
      final packed = base64Decode(stored.substring(prefix.length));
      if (packed.length < _nonceLength + _tagLength) return null;
      final box = SecretBox(
        packed.sublist(_nonceLength, packed.length - _tagLength),
        nonce: packed.sublist(0, _nonceLength),
        mac: Mac(packed.sublist(packed.length - _tagLength)),
      );
      final key = await _key();
      return utf8.decode(await _aes.decrypt(box, secretKey: key));
    } catch (_) {
      return null;
    }
  }

  /// Whether [stored] carries the ciphertext envelope.
  static bool isSealed(String? stored) => stored?.startsWith(prefix) ?? false;

  // ------------------------------------------- SharedPreferences helpers ---

  /// `prefs.getString` + [open]; a legacy plaintext value is lazily rewritten
  /// sealed before being returned, so reads migrate the store over time.
  static Future<String?> getString(SharedPreferences prefs, String key) async {
    final stored = prefs.getString(key);
    if (stored == null) return null;
    final value = await open(stored);
    if (!isSealed(stored) && value != null) {
      final sealed = await seal(value);
      // Re-check before writing: a login/refresh/logout that raced the async
      // seal must win — the migration only upgrades the value it read.
      if (prefs.getString(key) == stored) {
        await prefs.setString(key, sealed);
      }
    }
    return value;
  }

  static Future<void> setString(
      SharedPreferences prefs, String key, String value) async {
    await prefs.setString(key, await seal(value));
  }

  /// Element-wise [open] over a StringList. Elements that fail to decrypt are
  /// dropped (logged); if any element was legacy plaintext the whole list is
  /// rewritten sealed.
  static Future<List<String>> getStringList(
      SharedPreferences prefs, String key) async {
    final stored = prefs.getStringList(key);
    if (stored == null) return const [];
    var hadLegacy = false;
    var hadFailure = false;
    final out = <String>[];
    for (final element in stored) {
      final value = await open(element);
      if (value == null) {
        hadFailure = true;
        continue;
      }
      if (!isSealed(element)) hadLegacy = true;
      out.add(value);
    }
    if (hadFailure) {
      debugPrint('SecretVault: dropped undecryptable element(s) of "$key"');
    }
    // Migrate only off a CLEAN read: a rewrite that raced a transient
    // decrypt failure would delete the failed element permanently.
    if (hadLegacy && !hadFailure) {
      final sealed = <String>[];
      for (final value in out) {
        sealed.add(await seal(value));
      }
      // Same racing rule as getString: only migrate what was actually read.
      final current = prefs.getStringList(key);
      final unchanged = current != null &&
          current.length == stored.length &&
          () {
            for (var i = 0; i < current.length; i++) {
              if (current[i] != stored[i]) return false;
            }
            return true;
          }();
      if (unchanged) {
        await prefs.setStringList(key, sealed);
      }
    }
    return out;
  }

  static Future<void> setStringList(
      SharedPreferences prefs, String key, List<String> values) async {
    final sealed = <String>[];
    for (final value in values) {
      sealed.add(await seal(value));
    }
    await prefs.setStringList(key, sealed);
  }

  // ------------------------------------------------- JSON field helpers ---

  /// Returns a copy of [map] with the named string fields sealed (null and
  /// non-string fields are left untouched).
  static Future<Map<String, dynamic>> sealFields(
      Map<String, dynamic> map, List<String> fields) async {
    final out = Map<String, dynamic>.from(map);
    for (final field in fields) {
      final value = out[field];
      if (value is String) out[field] = await seal(value);
    }
    return out;
  }

  /// Returns a copy of [map] with the named fields opened. A field that fails
  /// to decrypt becomes null. Sets [legacySeen] semantics via the return
  /// record: `wasLegacy` is true when any named field was legacy plaintext
  /// (caller decides whether to rewrite the containing blob).
  static Future<({Map<String, dynamic> map, bool wasLegacy})> openFields(
      Map<String, dynamic> map, List<String> fields) async {
    final out = Map<String, dynamic>.from(map);
    var wasLegacy = false;
    for (final field in fields) {
      final value = out[field];
      if (value is! String) continue;
      if (!isSealed(value)) {
        wasLegacy = true;
        continue;
      }
      out[field] = await open(value);
    }
    return (map: out, wasLegacy: wasLegacy);
  }

  // ------------------------------------------------------------ key mgmt ---

  /// Kicks off key derivation (one device-info round trip) so the first real
  /// decrypt doesn't pay for it. Never throws.
  static Future<void> warmUp() async {
    try {
      await _key();
    } catch (_) {}
  }

  static Future<SecretKey> _key() => _keyFuture ??= _derive();

  /// Records which key-derivation source this install committed to, so the
  /// key can never silently FLIP between launches: a transient device-info
  /// failure must not derive a different (pepper-only) key, write fresh
  /// credentials under it, and strand them when the next launch succeeds.
  /// Values: `pepper`, or `id:<sha256(deviceId), first 16 bytes b64>`.
  /// Storing the hash leaks nothing useful — the key needs the id itself,
  /// which never touches the prefs file.
  static const String _keySourceKey = 'vault_key_source_v1';

  static Future<SecretKey> _derive() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = await _deviceId();
    // Retry transient lookup failures before committing to anything.
    for (var attempt = 0;
        deviceId == null && !_deviceIdOverridden && attempt < 2;
        attempt++) {
      await Future.delayed(const Duration(milliseconds: 200));
      deviceId = await _deviceId();
    }

    final marker = prefs.getString(_keySourceKey);
    if (marker == null) {
      await prefs.setString(_keySourceKey,
          deviceId == null ? 'pepper' : 'id:${await _idHash(deviceId)}');
    } else if (marker == 'pepper') {
      // This install committed to pepper-only (first launch couldn't resolve
      // an id). Stable-forever beats stronger-but-flipping: switching to the
      // id now would strand everything sealed since.
      deviceId = null;
    } else if (marker.startsWith('id:')) {
      if (deviceId == null) {
        // The id existed before and is gone this launch. Deriving the
        // fallback key here is exactly the corruption path this marker
        // prevents — fail instead: reads act signed-out (open() maps any
        // failure to null) and writes error out rather than sealing under a
        // key tomorrow can't reproduce.
        throw StateError(
            'SecretVault: device identity unavailable; refusing to derive '
            'a different key');
      }
      final hash = await _idHash(deviceId);
      if (marker != 'id:$hash') {
        // A genuinely different device identity (factory reset, restored
        // prefs on new hardware): the new key is CORRECT device-binding
        // behavior — old ciphertext reads as signed-out.
        await prefs.setString(_keySourceKey, 'id:$hash');
      }
    }

    final ikm = <int>[..._pepper, ...utf8.encode(deviceId ?? '')];
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: _hkdfSalt,
      info: utf8.encode('debrify-secret-vault-v1'),
    );
  }

  static Future<String> _idHash(String deviceId) async {
    final hash = await Sha256().hash(utf8.encode(deviceId));
    return base64Encode(hash.bytes.sublist(0, 16));
  }

  /// Best-effort stable PER-DEVICE identifier; null means pepper-only
  /// derivation (weaker, accepted). Android uses ANDROID_ID via a native
  /// channel — per app-signing-key + device since Android 8 and stable
  /// across OTAs. The build/model fields device_info_plus offers are shared
  /// by every unit of the same model and would bind nothing.
  static Future<String?> _deviceId() async {
    if (_deviceIdOverridden) return _deviceIdOverride;
    try {
      if (PlatformUtil.isTvOS) {
        // device_info_plus has no tvOS implementation; hand-rolled channel in
        // tvos/Runner/AppDelegate.swift.
        return await const MethodChannel('debrify/tvdevice')
            .invokeMethod<String>('id');
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Hand-rolled channel in MainActivity.kt (device_info_plus removed
        // its ANDROID_ID accessor).
        return await const MethodChannel('debrify/device')
            .invokeMethod<String>('id');
      }
      final plugin = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return (await plugin.iosInfo).identifierForVendor;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        return (await plugin.macOsInfo).systemGUID;
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        return (await plugin.windowsInfo).deviceId;
      }
      if (defaultTargetPlatform == TargetPlatform.linux) {
        return (await plugin.linuxInfo).machineId;
      }
    } catch (_) {}
    return null;
  }

  /// Resets memoized state; [deviceIdOverride] pins the ID for tests
  /// (pass null with the flag to exercise pepper-only mode).
  @visibleForTesting
  static void debugReset({String? deviceIdOverride}) {
    _keyFuture = null;
    _deviceIdOverridden = true;
    _deviceIdOverride = deviceIdOverride;
  }
}
