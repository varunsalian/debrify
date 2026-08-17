import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import 'package:flutter/foundation.dart';
import 'profile_scope.dart';

/// A paired device is device-trusted, not profile-authorized. This short-lived
/// lease is issued only after local profile unlock and is revoked on every
/// lock/switch. Remote peers can never select a profile or submit a PIN.
class ProfileRemoteLease {
  ProfileRemoteLease._();

  static final ProfileRemoteLease instance = ProfileRemoteLease._();
  DateTime Function() _clock = DateTime.now;

  String? _profileId;
  int? _generation;
  int? _sessionEpoch;
  int? _authorizationRevision;
  Set<ProfileFeature> _features = const <ProfileFeature>{};
  final Map<String, List<DateTime>> _attemptsByPeer =
      <String, List<DateTime>>{};
  final Map<String, DateTime> _peerSessions = <String, DateTime>{};
  static const Duration _peerLeaseTtl = Duration(minutes: 15);

  void authorize(UserProfile profile, ProfileScope scope) {
    _profileId = profile.id;
    _generation = scope.dataGeneration;
    _sessionEpoch = scope.sessionEpoch;
    _authorizationRevision = profile.authorizationRevision;
    _features = Set<ProfileFeature>.unmodifiable(profile.policy.enabled);
    _attemptsByPeer.clear();
    _peerSessions.clear();
  }

  void revoke() {
    _profileId = null;
    _generation = null;
    _sessionEpoch = null;
    _authorizationRevision = null;
    _features = const <ProfileFeature>{};
    _attemptsByPeer.clear();
    _peerSessions.clear();
  }

  bool bindAuthenticatedPeer({
    required String peerFingerprint,
    required String sessionId,
    required ProfileScope scope,
    required UserProfile currentProfile,
  }) {
    final now = _clock().toUtc();
    if (!_baseAllows(scope, currentProfile) ||
        peerFingerprint.isEmpty ||
        sessionId.isEmpty) {
      return false;
    }
    final key = _peerKey(peerFingerprint, sessionId);
    final existing = _peerSessions[key];
    // A live lease may follow the same paired peer onto a fresh transport
    // session (idle timeout/restart), but an expired lease cannot recreate
    // itself merely by reconnecting.
    if (existing != null) return existing.isAfter(now);
    final priorKeys = _peerSessions.keys
        .where((bound) => bound.startsWith('$peerFingerprint\u0000'))
        .toList(growable: false);
    if (priorKeys.isNotEmpty) {
      final hasLiveLease = priorKeys.any(
        (bound) => _peerSessions[bound]!.isAfter(now),
      );
      if (!hasLiveLease) return false;
      for (final prior in priorKeys) {
        _peerSessions.remove(prior);
        _attemptsByPeer.remove(prior);
      }
    }
    _peerSessions[key] = now.add(_peerLeaseTtl);
    return true;
  }

  bool allows(
    ProfileFeature feature,
    ProfileScope scope, {
    required UserProfile currentProfile,
    required String peerFingerprint,
    required String sessionId,
    bool rateLimit = true,
  }) {
    final now = _clock().toUtc();
    final key = _peerKey(peerFingerprint, sessionId);
    if (rateLimit) {
      final attempts = _attemptsByPeer.putIfAbsent(key, () => <DateTime>[]);
      attempts.removeWhere(
        (attempt) => now.difference(attempt) > const Duration(seconds: 10),
      );
      if (attempts.length >= 60) return false;
      attempts.add(now);
    }
    final expiresAt = _peerSessions[key];
    if (expiresAt == null || !expiresAt.isAfter(now)) return false;
    final allowed =
        _baseAllows(scope, currentProfile) && _features.contains(feature);
    if (allowed) _peerSessions[key] = now.add(_peerLeaseTtl);
    return allowed;
  }

  bool _baseAllows(ProfileScope scope, UserProfile currentProfile) =>
      _profileId == scope.profileId &&
      _generation == scope.dataGeneration &&
      _sessionEpoch == scope.sessionEpoch &&
      _authorizationRevision != null &&
      currentProfile.id == _profileId &&
      currentProfile.isEnabled &&
      currentProfile.authorizationRevision == _authorizationRevision;

  static String _peerKey(String fingerprint, String sessionId) =>
      '$fingerprint\u0000$sessionId';

  @visibleForTesting
  void debugSetClock(DateTime Function()? clock) {
    _clock = clock ?? DateTime.now;
  }
}
