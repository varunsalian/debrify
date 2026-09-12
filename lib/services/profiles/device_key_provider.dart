import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Process-wide device vault selected before profile resource services open.
/// Linux unlocks locally by default; existing passphrase vaults require one
/// unlock before opting into local storage. Other platforms use native keys.
class DeviceKeyProvider {
  DeviceKeyProvider._();

  static const String linuxStateKey = 'profiles_linux_wrapped_key_v1';
  static DeviceSecretCipher? _cipher;
  static bool _initialized = false;
  static Future<void>? _initializing;
  @visibleForTesting
  static bool? debugLinuxOverride;

  static bool get isLinux => debugLinuxOverride ?? Platform.isLinux;

  static bool get isInitialized => _initialized;
  static bool get isUnlocked => _cipher != null;
  static DeviceSecretCipher get cipher =>
      _cipher ?? (throw StateError('Device vault is locked'));

  static Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  static Future<void> _initialize() async {
    await removeScopedLinuxVaultCopies();
    if (isLinux) {
      final source = (await SharedPreferences.getInstance()).getString(
        linuxStateKey,
      );
      if (source == null) {
        final secret = base64Encode(
          PassphraseDeviceSecretCipher._randomBytes(32),
        );
        final provider = await PassphraseDeviceSecretCipher.create(secret);
        provider.state = provider.state.withLocalUnlock(secret);
        await _persistLinuxProvider(provider);
      } else {
        final state = LinuxWrappedDeviceKey.decode(source);
        final secret = state.localUnlockSecret;
        if (secret != null) {
          final provider = PassphraseDeviceSecretCipher(state);
          await provider.unlock(secret);
          _cipher = provider;
        }
      }
      _initialized = true;
      return;
    }
    final platform = PlatformDeviceSecretCipher();
    await platform.initialize();
    _cipher = platform;
    _initialized = true;
  }

  /// Repair older migrations that copied this device-only secret into profile
  /// generations. Match the entire physical key; never remove the device entry
  /// or similarly named user preferences. Also run before restoring protection.
  static Future<void> removeScopedLinuxVaultCopies() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = RegExp(
      '^p\\.[^.]+\\.g\\.[0-9]+\\.${RegExp.escape(linuxStateKey)}\$',
    );
    for (final key in prefs.getKeys().where(scopedKey.hasMatch).toList()) {
      if (!await prefs.remove(key)) {
        throw StateError('Could not remove scoped device vault state');
      }
    }
  }

  static Future<bool> linuxHasWrappedKey() async {
    if (!isLinux) return false;
    return (await SharedPreferences.getInstance()).containsKey(linuxStateKey);
  }

  static Future<void> createLinuxVault(String passphrase) async {
    if (!isLinux) throw UnsupportedError('Linux only');
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(linuxStateKey)) {
      throw StateError('Linux vault already exists');
    }
    final provider = await PassphraseDeviceSecretCipher.create(passphrase);
    if (!await prefs.setString(linuxStateKey, provider.state.encode())) {
      throw StateError('Could not persist Linux vault state');
    }
    _cipher = provider;
    _initialized = true;
  }

  static Future<void> unlockLinuxVault(String passphrase) async {
    if (!isLinux) throw UnsupportedError('Linux only');
    final source = (await SharedPreferences.getInstance()).getString(
      linuxStateKey,
    );
    if (source == null) throw StateError('Linux vault is not configured');
    final provider = PassphraseDeviceSecretCipher(
      LinuxWrappedDeviceKey.decode(source),
    );
    await provider.unlock(passphrase);
    _cipher = provider;
    _initialized = true;
  }

  static bool get linuxAutoUnlockEnabled =>
      _cipher is PassphraseDeviceSecretCipher &&
      (_cipher as PassphraseDeviceSecretCipher).state.localUnlockSecret != null;

  static Future<void> _persistLinuxProvider(
    PassphraseDeviceSecretCipher provider,
  ) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      linuxStateKey,
      provider.state.encode(),
    )) {
      throw StateError('Could not persist Linux vault state');
    }
    _cipher = provider;
  }

  /// Rewrap the same device key, preserving all existing encrypted resources.
  /// Publish only after the replacement state has been saved successfully.
  static Future<void> changeLinuxPassphrase(String nextPassphrase) async {
    await _rewrapLinuxKey(nextPassphrase, automatic: false);
  }

  static Future<void> enableLinuxAutoUnlock() async {
    if (linuxAutoUnlockEnabled) return;
    await _rewrapLinuxKey(
      base64Encode(PassphraseDeviceSecretCipher._randomBytes(32)),
      automatic: true,
    );
  }

  static Future<void> _rewrapLinuxKey(
    String secret, {
    required bool automatic,
  }) async {
    final current = _cipher;
    if (!isLinux ||
        current is! PassphraseDeviceSecretCipher ||
        current._key == null) {
      throw StateError('Linux vault is locked');
    }
    final replacement = PassphraseDeviceSecretCipher(current.state)
      .._key = current._key;
    await replacement.changePassphrase(secret);
    if (automatic) {
      replacement.state = replacement.state.withLocalUnlock(secret);
    }
    await removeScopedLinuxVaultCopies();
    await _persistLinuxProvider(replacement);
  }

  static void lockLinuxVault() {
    final provider = _cipher;
    if (provider is PassphraseDeviceSecretCipher) provider.lock();
    if (isLinux) _cipher = null;
  }

  static Future<void> destroy() async {
    if (isLinux) {
      await (await SharedPreferences.getInstance()).remove(linuxStateKey);
    } else {
      await const MethodChannel(
        'debrify/device_secret',
      ).invokeMethod<void>('destroy');
    }
    _cipher = null;
    _initialized = false;
  }

  @visibleForTesting
  static void debugReset() {
    _initializing = null;
    _cipher = null;
    _initialized = false;
    debugLinuxOverride = null;
  }

  @visibleForTesting
  static void debugInstallCipher(DeviceSecretCipher cipher) {
    _cipher = cipher;
    _initialized = true;
  }
}

abstract interface class DeviceSecretCipher {
  Future<void> initialize();
  Future<String> seal(List<int> plaintext, {required List<int> associatedData});
  Future<List<int>> open(String envelope, {required List<int> associatedData});
}

/// Hardware/OS-backed implementation. The key never crosses the method
/// channel: native code performs authenticated encryption and returns only an
/// opaque envelope. Linux intentionally requires the passphrase provider.
class PlatformDeviceSecretCipher implements DeviceSecretCipher {
  static const MethodChannel _channel = MethodChannel('debrify/device_secret');

  @override
  Future<void> initialize() async {
    if (DeviceKeyProvider.isLinux) {
      throw StateError('Linux device vault requires an unlocked passphrase');
    }
    final ready = await _channel.invokeMethod<bool>('initialize');
    if (ready != true) throw StateError('Device secret store is unavailable');
  }

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    final value = await _channel.invokeMethod<String>('seal', <String, Object>{
      'plaintext': base64Encode(plaintext),
      'associatedData': base64Encode(associatedData),
    });
    if (value == null) throw StateError('Device secret encryption failed');
    return 'native1:$value';
  }

  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    if (!envelope.startsWith('native1:')) {
      throw const FormatException('Unsupported device secret envelope');
    }
    final value = await _channel.invokeMethod<String>('open', <String, Object>{
      'envelope': envelope.substring('native1:'.length),
      'associatedData': base64Encode(associatedData),
    });
    if (value == null) throw StateError('Device secret decryption failed');
    return base64Decode(value);
  }
}

/// Explicit Linux fallback when Secret Service is unavailable. Resource data
/// uses a random device key; the passphrase derives only a wrapping key.
class PassphraseDeviceSecretCipher implements DeviceSecretCipher {
  LinuxWrappedDeviceKey state;
  SecretKey? _key;

  PassphraseDeviceSecretCipher(this.state);

  static Future<PassphraseDeviceSecretCipher> create(String passphrase) async {
    _validatePassphrase(passphrase);
    final salt = _randomBytes(16);
    final deviceKeyBytes = _randomBytes(32);
    final wrappingKey = await _deriveWrappingKey(passphrase, salt);
    final wrapped = await _wrapDeviceKey(deviceKeyBytes, wrappingKey);
    final keyId = await _keyId(deviceKeyBytes);
    final provider = PassphraseDeviceSecretCipher(
      LinuxWrappedDeviceKey(salt: salt, wrappedKey: wrapped, keyId: keyId),
    );
    provider._key = SecretKey(deviceKeyBytes);
    return provider;
  }

  Future<void> unlock(String passphrase) async {
    _validatePassphrase(passphrase);
    final wrappingKey = await _deriveWrappingKey(passphrase, state.salt);
    final deviceKeyBytes = await _unwrapDeviceKey(
      state.wrappedKey,
      wrappingKey,
    );
    if (await _keyId(deviceKeyBytes) != state.keyId) {
      throw StateError('Linux device vault verifier mismatch');
    }
    _key = SecretKey(deviceKeyBytes);
  }

  Future<void> changePassphrase(String nextPassphrase) async {
    _validatePassphrase(nextPassphrase);
    final key = _key ?? (throw StateError('Linux device vault is locked'));
    final bytes = await key.extractBytes();
    final salt = _randomBytes(16);
    final wrappingKey = await _deriveWrappingKey(nextPassphrase, salt);
    state = LinuxWrappedDeviceKey(
      salt: salt,
      wrappedKey: await _wrapDeviceKey(bytes, wrappingKey),
      keyId: state.keyId,
    );
  }

  void lock() => _key = null;

  @override
  Future<void> initialize() async {
    if (_key == null) throw StateError('Linux device vault is locked');
  }

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    final key = _key ?? (throw StateError('Linux device vault is locked'));
    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: key,
      aad: associatedData,
    );
    return 'linux1:${state.keyId}:${base64Encode(<int>[...box.nonce, ...box.cipherText, ...box.mac.bytes])}';
  }

  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    final key = _key ?? (throw StateError('Linux device vault is locked'));
    final prefix = 'linux1:${state.keyId}:';
    if (!envelope.startsWith(prefix)) {
      throw const FormatException('Unsupported passphrase secret envelope');
    }
    final packed = base64Decode(envelope.substring(prefix.length));
    if (packed.length < 28) {
      throw const FormatException('Corrupt secret envelope');
    }
    final box = SecretBox(
      packed.sublist(12, packed.length - 16),
      nonce: packed.sublist(0, 12),
      mac: Mac(packed.sublist(packed.length - 16)),
    );
    return AesGcm.with256bits().decrypt(
      box,
      secretKey: key,
      aad: associatedData,
    );
  }

  static Future<SecretKey> _deriveWrappingKey(
    String passphrase,
    List<int> salt,
  ) => Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

  static Future<String> _wrapDeviceKey(
    List<int> deviceKey,
    SecretKey wrappingKey,
  ) async {
    final box = await AesGcm.with256bits().encrypt(
      deviceKey,
      secretKey: wrappingKey,
      aad: utf8.encode('debrify-linux-device-key-v1'),
    );
    return base64Encode(<int>[
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<List<int>> _unwrapDeviceKey(
    String wrapped,
    SecretKey wrappingKey,
  ) async {
    final packed = base64Decode(wrapped);
    if (packed.length != 60) throw const FormatException('Invalid wrapped key');
    return AesGcm.with256bits().decrypt(
      SecretBox(
        packed.sublist(12, 44),
        nonce: packed.sublist(0, 12),
        mac: Mac(packed.sublist(44)),
      ),
      secretKey: wrappingKey,
      aad: utf8.encode('debrify-linux-device-key-v1'),
    );
  }

  static Future<String> _keyId(List<int> key) async {
    final hash = await Sha256().hash(key);
    return base64UrlEncode(hash.bytes.sublist(0, 12)).replaceAll('=', '');
  }

  static void _validatePassphrase(String passphrase) {
    if (passphrase.length < 8) {
      throw ArgumentError.value(
        passphrase,
        'passphrase',
        'Minimum 8 characters',
      );
    }
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

class LinuxWrappedDeviceKey {
  final List<int> salt;
  final String wrappedKey;
  final String keyId;
  final String? localUnlockSecret;

  const LinuxWrappedDeviceKey({
    required this.salt,
    required this.wrappedKey,
    required this.keyId,
    this.localUnlockSecret,
  });

  factory LinuxWrappedDeviceKey.decode(String source) {
    final json = jsonDecode(source);
    if (json is! Map || json['version'] != 1) {
      throw const FormatException('Invalid Linux device-key state');
    }
    final salt = base64Decode(json['salt']! as String);
    final wrapped = json['wrappedKey'];
    final keyId = json['keyId'];
    if (salt.length != 16 || wrapped is! String || keyId is! String) {
      throw const FormatException('Invalid Linux device-key state');
    }
    final local = json['localUnlockSecret'];
    if (local != null &&
        (local is! String || base64Decode(local).length != 32)) {
      throw const FormatException('Invalid local unlock secret');
    }
    return LinuxWrappedDeviceKey(
      salt: salt,
      wrappedKey: wrapped,
      keyId: keyId,
      localUnlockSecret: local as String?,
    );
  }

  LinuxWrappedDeviceKey withLocalUnlock(String secret) => LinuxWrappedDeviceKey(
    salt: salt,
    wrappedKey: wrappedKey,
    keyId: keyId,
    localUnlockSecret: secret,
  );

  String encode() => jsonEncode(<String, Object>{
    'version': 1,
    'salt': base64Encode(salt),
    'wrappedKey': wrappedKey,
    'keyId': keyId,
    if (localUnlockSecret != null) 'localUnlockSecret': localUnlockSecret!,
  });
}

@visibleForTesting
class MemoryDeviceSecretCipher implements DeviceSecretCipher {
  final SecretKey _key;

  MemoryDeviceSecretCipher([List<int>? key])
    : _key = SecretKey(key ?? _randomBytes(32));

  @override
  Future<void> initialize() async {}

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: _key,
      aad: associatedData,
    );
    return 'memory1:${base64Encode(<int>[...box.nonce, ...box.cipherText, ...box.mac.bytes])}';
  }

  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    if (!envelope.startsWith('memory1:')) {
      throw const FormatException('Unsupported test secret envelope');
    }
    final packed = base64Decode(envelope.substring('memory1:'.length));
    final box = SecretBox(
      packed.sublist(12, packed.length - 16),
      nonce: packed.sublist(0, 12),
      mac: Mac(packed.sublist(packed.length - 16)),
    );
    return AesGcm.with256bits().decrypt(
      box,
      secretKey: _key,
      aad: associatedData,
    );
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
