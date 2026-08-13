import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../secret_vault.dart';
import 'remote_session.dart';

/// Persistence for the remote-control protocol's long-term identities:
/// this device's static X25519 keypair, the peers a receiver has paired with
/// (SAS completed once — later transfers skip the code), and the receivers a
/// sender has seen speak v2 (downgrade pinning).
class RemotePairingStore {
  RemotePairingStore._();

  static const String _keypairKey = 'remote_static_keypair_v1';
  static const String _pairedKey = 'remote_paired_devices_v1';
  static const String _knownReceiversKey = 'remote_known_receivers_v1';

  static Future<SimpleKeyPair>? _keyPairFuture;

  /// This device's static keypair, created on first use. The private key is
  /// sealed by [SecretVault] like every other stored secret.
  static Future<SimpleKeyPair> loadOrCreateKeypair() =>
      _keyPairFuture ??= _loadOrCreate();

  static Future<SimpleKeyPair> _loadOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await SecretVault.getString(prefs, _keypairKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        return await RemoteSessionCrypto.x25519
            .newKeyPairFromSeed(base64Decode(stored));
      } catch (e) {
        debugPrint('RemotePairingStore: stored keypair unusable ($e), '
            'generating a new identity');
      }
    }
    final keyPair = await RemoteSessionCrypto.x25519.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    await SecretVault.setString(prefs, _keypairKey, base64Encode(seed));
    return keyPair;
  }

  /// This device's static public key, for the discovery advertisement.
  static Future<List<int>> publicKeyBytes() async {
    final keyPair = await loadOrCreateKeypair();
    return (await keyPair.extractPublicKey()).bytes;
  }

  // -------------------------------------------------- paired (receiver) ---

  static Future<List<PairedDevice>> listPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pairedKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) PairedDevice.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Record a completed SAS pairing. Written even when remembering is
  /// disabled, so enabling the flag later works retroactively.
  static Future<void> rememberPeer({
    required String fingerprint,
    required List<int> staticKey,
    required String name,
  }) async {
    final devices = await listPaired();
    final kept =
        devices.where((d) => d.fingerprint != fingerprint).toList();
    kept.add(PairedDevice(
      fingerprint: fingerprint,
      staticKey: base64Encode(staticKey),
      name: name,
      pairedAt: DateTime.now().toUtc(),
      lastUsedAt: DateTime.now().toUtc(),
    ));
    await _writePaired(kept);
  }

  static Future<void> touchPeer(String fingerprint) async {
    final devices = await listPaired();
    var changed = false;
    final updated = [
      for (final device in devices)
        if (device.fingerprint == fingerprint && (changed = true))
          device.copyWith(lastUsedAt: DateTime.now().toUtc())
        else
          device,
    ];
    if (changed) await _writePaired(updated);
  }

  static Future<bool> isRemembered(String fingerprint) async =>
      (await listPaired()).any((d) => d.fingerprint == fingerprint);

  static Future<void> forget(String fingerprint) async {
    final devices = await listPaired();
    await _writePaired(
        devices.where((d) => d.fingerprint != fingerprint).toList());
  }

  static Future<void> forgetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairedKey);
  }

  static Future<void> _writePaired(List<PairedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pairedKey,
      jsonEncode([for (final d in devices) d.toJson()]),
    );
  }

  // -------------------------------------------- known receivers (sender) ---

  /// Pin that [name]/[fingerprint] spoke v2. Used to refuse silent downgrades
  /// and to warn when a known TV's identity key changes.
  ///
  /// Keyed by FINGERPRINT, not name: two TVs left on the default "Debrify TV"
  /// name must each keep their own pin — name-keyed replacement made pairing
  /// the second one clobber (or be blocked by) the first.
  static Future<void> pinReceiver({
    required String fingerprint,
    required List<int> staticKey,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final known = await knownReceivers();
    final kept = known.where((r) => r.fingerprint != fingerprint).toList();
    kept.add(KnownReceiver(
      name: name,
      fingerprint: fingerprint,
      staticKey: base64Encode(staticKey),
      pinnedAt: DateTime.now().toUtc(),
    ));
    await prefs.setString(
      _knownReceiversKey,
      jsonEncode([for (final r in kept) r.toJson()]),
    );
  }

  static Future<List<KnownReceiver>> knownReceivers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_knownReceiversKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) KnownReceiver.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// All pins under a display name — names are NOT unique across devices.
  static Future<List<KnownReceiver>> knownReceiversNamed(String name) async =>
      (await knownReceivers()).where((r) => r.name == name).toList();

  static Future<bool> isPinnedFingerprint(String fingerprint) async =>
      (await knownReceivers()).any((r) => r.fingerprint == fingerprint);

  @visibleForTesting
  static void debugResetKeypairCache() {
    _keyPairFuture = null;
  }
}

class PairedDevice {
  final String fingerprint;
  final String staticKey; // base64
  final String name;
  final DateTime pairedAt;
  final DateTime lastUsedAt;

  const PairedDevice({
    required this.fingerprint,
    required this.staticKey,
    required this.name,
    required this.pairedAt,
    required this.lastUsedAt,
  });

  PairedDevice copyWith({DateTime? lastUsedAt}) => PairedDevice(
        fingerprint: fingerprint,
        staticKey: staticKey,
        name: name,
        pairedAt: pairedAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() => {
        'fp': fingerprint,
        'spk': staticKey,
        'name': name,
        'pairedAt': pairedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        fingerprint: json['fp'] as String,
        staticKey: json['spk'] as String? ?? '',
        name: json['name'] as String? ?? 'Phone',
        pairedAt:
            DateTime.tryParse(json['pairedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        lastUsedAt:
            DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class KnownReceiver {
  final String name;
  final String fingerprint;
  final String staticKey; // base64
  final DateTime pinnedAt;

  const KnownReceiver({
    required this.name,
    required this.fingerprint,
    required this.staticKey,
    required this.pinnedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'fp': fingerprint,
        'spk': staticKey,
        'pinnedAt': pinnedAt.toIso8601String(),
      };

  factory KnownReceiver.fromJson(Map<String, dynamic> json) => KnownReceiver(
        name: json['name'] as String? ?? '',
        fingerprint: json['fp'] as String? ?? '',
        staticKey: json['spk'] as String? ?? '',
        pinnedAt: DateTime.tryParse(json['pinnedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
