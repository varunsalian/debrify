import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../models/profiles/profile_policy.dart';
import 'profile_authorization.dart';
import 'profile_registry.dart';

enum ProfilePinResult {
  verified,
  invalid,
  locked,
  resetRequired,
  notConfigured,
}

/// Outcome of a recovery-code attempt.
enum ProfileRecoveryResult {
  /// Code matched: the PIN and the (one-shot) code are cleared; the profile
  /// opens without a PIN until a new one is set.
  cleared,
  invalid,

  /// The profile has no PIN, or its PIN predates recovery codes (set before
  /// this feature; a code is minted on the next PIN change).
  notConfigured,
}

class ProfilePinVerification {
  final ProfilePinResult result;
  final DateTime? lockedUntil;

  const ProfilePinVerification(this.result, {this.lockedUntil});
}

class ProfilePinService {
  final ProfileRegistry registry;
  final DateTime Function() _clock;
  final PinKdfParams params;

  ProfilePinService({
    required this.registry,
    DateTime Function()? clock,
    this.params = const PinKdfParams(),
  }) : _clock = clock ?? DateTime.now;

  Future<void> setPin(String profileId, String pin) async {
    _validatePin(pin);
    final salt = _randomBytes(16);
    final hash = await _derive(pin, salt, params);
    await registry.setPinRecord(
      profileId: profileId,
      hash: hash,
      salt: salt,
      paramsJson: jsonEncode(params.toJson()),
    );
  }

  Future<void> removePin(String profileId) => registry.setPinRecord(
    profileId: profileId,
    hash: null,
    salt: null,
    paramsJson: null,
  );

  /// Assigns a replacement PIN only after revalidating the currently active
  /// managing Admin. The lower-level [setPin] is restricted by the registry to
  /// pre-commit bootstrap/migration; live installs must use this method.
  ///
  /// Returns the freshly minted recovery code — the ONLY time it exists in
  /// the clear. The caller must show it to the user once; only its hash is
  /// stored, and every PIN change rotates it.
  Future<String> setPinAsAdmin({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
    required String pin,
  }) async {
    _validatePin(pin);
    final salt = _randomBytes(16);
    final hash = await _derive(pin, salt, params);
    final recoveryCode = _generateRecoveryCode();
    final recoverySalt = _randomBytes(16);
    final recoveryHash = await _derive(
      _normalizeRecoveryCode(recoveryCode),
      recoverySalt,
      params,
    );
    // KDF work is intentionally complete before the final actor check. The
    // registry repeats this authority condition inside the write transaction.
    await _authorizeAdmin(actor, targetProfileId);
    await registry.setPinRecord(
      profileId: targetProfileId,
      hash: hash,
      salt: salt,
      paramsJson: jsonEncode(params.toJson()),
      recoveryHash: recoveryHash,
      recoverySalt: recoverySalt,
      recoveryParamsJson: jsonEncode(params.toJson()),
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    return recoveryCode;
  }

  /// Self-service escape hatch for a forgotten PIN: a matching recovery code
  /// removes the PIN entirely (and spends the code), letting the user in to
  /// set a fresh one. Deliberately NOT throttled by the PIN lock — the code
  /// has ~50 bits of entropy, so online guessing is not a real threat, and
  /// its whole purpose is working when the PIN path is exhausted.
  Future<ProfileRecoveryResult> verifyRecoveryCode(
    String profileId,
    String code,
  ) async {
    final record = await registry.getPinRecord(profileId);
    if (record == null) throw StateError('Profile does not exist');
    // Admin-reset state is a deliberate lockdown (possibly a compromised
    // PIN); the pre-reset recovery code must not quietly undo it.
    if (record.resetRequired ||
        !record.hasPin ||
        !record.hasRecoveryCode) {
      return ProfileRecoveryResult.notConfigured;
    }
    final normalized = _normalizeRecoveryCode(code);
    if (normalized.length != _recoveryCodeLength ||
        normalized.codeUnits.any(
          (unit) => !_recoveryAlphabet.codeUnits.contains(unit),
        )) {
      return ProfileRecoveryResult.invalid;
    }
    final PinKdfParams storedParams;
    try {
      final decoded = jsonDecode(record.recoveryParamsJson!);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid recovery parameter record');
      }
      storedParams = PinKdfParams.fromJson(decoded);
    } catch (_) {
      return ProfileRecoveryResult.invalid;
    }
    final List<int> candidate;
    try {
      candidate = await _derive(normalized, record.recoverySalt!, storedParams);
    } catch (_) {
      return ProfileRecoveryResult.invalid;
    }
    if (!_constantTimeEquals(candidate, record.recoveryHash!)) {
      return ProfileRecoveryResult.invalid;
    }
    final cleared = await registry.clearPinViaRecoveryIfUnchanged(
      profileId: profileId,
      expected: record,
    );
    if (!cleared) throw StateError('PIN authorization changed');
    return ProfileRecoveryResult.cleared;
  }

  /// Removes PIN protection without ever revealing or verifying the old PIN.
  Future<void> removePinAsAdmin({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
  }) async {
    await _authorizeAdmin(actor, targetProfileId);
    await registry.setPinRecord(
      profileId: targetProfileId,
      hash: null,
      salt: null,
      paramsJson: null,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
  }

  Future<void> _authorizeAdmin(
    ProfileAuthorizationContext actor,
    String targetProfileId,
  ) async {
    final profile = await actor.validate(registry);
    if (profile.role != UserProfileRole.admin ||
        !profile.allows(ProfileFeature.manageProfiles)) {
      throw StateError('PIN reset requires an Admin');
    }
    final target = await registry.getProfile(targetProfileId);
    if (target == null || !target.isEnabled) {
      throw StateError('Target profile is unavailable');
    }
  }

  /// Marks a formerly protected profile inaccessible until an authenticated
  /// Admin assigns a replacement PIN or explicitly removes protection. The
  /// repair is conditional so a stale verifier cannot erase a newer PIN.
  Future<void> requireAdminReset(
    String profileId, {
    ProfilePinRecord? expected,
  }) async {
    final observed = expected ?? await registry.getPinRecord(profileId);
    if (observed == null) throw StateError('Profile does not exist');
    final changed = await registry.markPinResetRequiredIfUnchanged(
      profileId: profileId,
      expected: observed,
    );
    if (!changed) throw StateError('PIN authorization changed');
  }

  Future<ProfilePinVerification> verify(String profileId, String pin) async {
    final record = await registry.getPinRecord(profileId);
    if (record == null) throw StateError('Profile does not exist');
    if (record.resetRequired) {
      return const ProfilePinVerification(ProfilePinResult.resetRequired);
    }
    if (record.isCorrupt) {
      await requireAdminReset(profileId, expected: record);
      return const ProfilePinVerification(ProfilePinResult.resetRequired);
    }
    if (!record.hasPin) {
      return const ProfilePinVerification(ProfilePinResult.notConfigured);
    }
    final now = _clock();
    final nowMs = now.millisecondsSinceEpoch;
    if (record.lockedUntilMs case final lockedUntil?) {
      // Corrupt/far-future timestamps are capped to one hour so clock rollback
      // cannot create a permanent lock while still failing conservatively.
      final capped = min(
        lockedUntil,
        nowMs + const Duration(hours: 1).inMilliseconds,
      );
      if (capped != lockedUntil) {
        final normalized = await registry.normalizePinLockIfUnchanged(
          profileId: profileId,
          lockedUntilMs: capped,
          expected: record,
        );
        if (!normalized) throw StateError('PIN authorization changed');
      }
      if (capped > nowMs) {
        return ProfilePinVerification(
          ProfilePinResult.locked,
          lockedUntil: DateTime.fromMillisecondsSinceEpoch(capped),
        );
      }
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      return _failed(profileId, nowMs, record);
    }
    if (record.hash!.length != 32 ||
        record.salt!.length < 8 ||
        record.salt!.length > 64) {
      await requireAdminReset(profileId, expected: record);
      return const ProfilePinVerification(ProfilePinResult.resetRequired);
    }
    final PinKdfParams storedParams;
    try {
      final decoded = jsonDecode(record.paramsJson!);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid PIN parameter record');
      }
      storedParams = PinKdfParams.fromJson(decoded);
    } catch (_) {
      await requireAdminReset(profileId, expected: record);
      return const ProfilePinVerification(ProfilePinResult.resetRequired);
    }
    final List<int> candidate;
    try {
      candidate = await _derive(pin, record.salt!, storedParams);
    } catch (_) {
      await requireAdminReset(profileId, expected: record);
      return const ProfilePinVerification(ProfilePinResult.resetRequired);
    }
    if (!_constantTimeEquals(candidate, record.hash!)) {
      return _failed(profileId, nowMs, record);
    }
    List<int>? replacementHash;
    List<int>? replacementSalt;
    if (storedParams != params) {
      replacementSalt = _randomBytes(16);
      replacementHash = await _derive(pin, replacementSalt, params);
    }
    final completed = await registry.completePinVerificationIfUnchanged(
      profileId: profileId,
      expected: record,
      replacementHash: replacementHash,
      replacementSalt: replacementSalt,
      replacementParamsJson: replacementHash == null
          ? null
          : jsonEncode(params.toJson()),
    );
    if (!completed) throw StateError('PIN authorization changed');
    return const ProfilePinVerification(ProfilePinResult.verified);
  }

  Future<ProfilePinVerification> _failed(
    String profileId,
    int nowMs,
    ProfilePinRecord expected,
  ) async {
    final updated = await registry.recordPinFailureIfUnchanged(
      profileId: profileId,
      nowMs: nowMs,
      expected: expected,
    );
    if (updated == null) throw StateError('PIN authorization changed');
    return ProfilePinVerification(
      ProfilePinResult.invalid,
      lockedUntil: updated.lockedUntilMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updated.lockedUntilMs!),
    );
  }

  static void _validatePin(String pin) {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN must contain 4–8 digits');
    }
  }

  /// No 0/O/1/I/L: every character survives handwriting on a sticky note.
  static const String _recoveryAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int _recoveryCodeLength = 10;

  /// ~49.5 bits of entropy, shown grouped (XXXXX-XXXXX) for transcription.
  static String _generateRecoveryCode() {
    final random = Random.secure();
    final code = List<String>.generate(
      _recoveryCodeLength,
      (_) => _recoveryAlphabet[random.nextInt(_recoveryAlphabet.length)],
    ).join();
    return '${code.substring(0, 5)}-${code.substring(5)}';
  }

  /// Entry is forgiving: case, spaces, and dashes never matter.
  static String _normalizeRecoveryCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Future<List<int>> _derive(
    String pin,
    List<int> salt,
    PinKdfParams params,
  ) => compute(_derivePinHash, <String, Object>{
    'pin': pin,
    'salt': salt,
    ...params.toJson(),
  });

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.isEmpty || b.isEmpty) return false;
    var difference = a.length ^ b.length;
    final longest = max(a.length, b.length);
    for (var index = 0; index < longest; index++) {
      difference |= a[index % a.length] ^ b[index % b.length];
    }
    return difference == 0;
  }
}

Future<List<int>> _derivePinHash(Map<String, Object> input) async {
  final key =
      await Argon2id(
        parallelism: input['parallelism']! as int,
        memory: input['memory']! as int,
        iterations: input['iterations']! as int,
        hashLength: 32,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(input['pin']! as String)),
        nonce: input['salt']! as List<int>,
      );
  return key.extractBytes();
}

class PinKdfParams {
  final int memory;
  final int iterations;
  final int parallelism;

  const PinKdfParams({
    this.memory = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  factory PinKdfParams.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported PIN KDF version');
    }
    final memory = json['memory'];
    final iterations = json['iterations'];
    final parallelism = json['parallelism'];
    if (memory is! int ||
        iterations is! int ||
        parallelism is! int ||
        memory < 8 ||
        memory > 131072 ||
        iterations < 1 ||
        iterations > 16 ||
        parallelism < 1 ||
        parallelism > 8 ||
        memory < 8 * parallelism) {
      throw const FormatException('Invalid PIN KDF parameters');
    }
    return PinKdfParams(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
    );
  }

  Map<String, int> toJson() => <String, int>{
    'version': 1,
    'memory': memory,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  @override
  bool operator ==(Object other) =>
      other is PinKdfParams &&
      other.memory == memory &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memory, iterations, parallelism);
}
