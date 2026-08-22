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

  /// Reissues the local profile authorization after a mutation that the user
  /// explicitly approved through the remote-import confirmation dialog.
  ///
  /// Connection collection writes intentionally bump the profile's
  /// authorization revision. That must revoke every previously issued peer
  /// lease, but it must not strand the one authenticated peer whose mutation
  /// the user just approved. Start from a clean authorization and bind only
  /// that peer/session to the new revision.
  bool reauthorizeApprovedPeer({
    required UserProfile profile,
    required ProfileScope scope,
    required String peerFingerprint,
    required String sessionId,
  }) {
    authorize(profile, scope);
    return bindAuthenticatedPeer(
      peerFingerprint: peerFingerprint,
      sessionId: sessionId,
      scope: scope,
      currentProfile: profile,
    );
  }

  /// Carries a still-live peer lease across an ordinary profile authority
  /// revision after the receiver has independently proved that this is a
  /// persisted remembered device. A lock/switch/restart calls [revoke] (or
  /// changes the scope), and an expired peer has no live entry, so neither can
  /// silently use this renewal path.
  bool renewRememberedPeerAfterRevision({
    required UserProfile profile,
    required ProfileScope scope,
    required String peerFingerprint,
    required String sessionId,
  }) {
    final now = _clock().toUtc();
    final key = _peerKey(peerFingerprint, sessionId);
    final priorKeys = _peerSessions.keys
        .where((bound) => bound.startsWith('$peerFingerprint\u0000'))
        .toList(growable: false);
    final livePeer =
        (_peerSessions[key]?.isAfter(now) ?? false) ||
        priorKeys.any((bound) => _peerSessions[bound]!.isAfter(now));
    final sameUnlockedScope =
        _profileId == scope.profileId &&
        _generation == scope.dataGeneration &&
        _sessionEpoch == scope.sessionEpoch &&
        profile.id == _profileId &&
        profile.isEnabled;
    final revisionChanged =
        _authorizationRevision != null &&
        _authorizationRevision != profile.authorizationRevision;
    if (!livePeer || !sameUnlockedScope || !revisionChanged) {
      return false;
    }
    authorize(profile, scope);
    return bindAuthenticatedPeer(
      peerFingerprint: peerFingerprint,
      sessionId: sessionId,
      scope: scope,
      currentProfile: profile,
    );
  }

  /// Refreshes an unlocked profile whose authority revision changed before
  /// any remote peer had been admitted. This can happen while startup work
  /// reconciles profile-owned resources after the local unlock.
  ///
  /// Once any peer lease has been issued, including an expired one, revision
  /// renewal must use [renewRememberedPeerAfterRevision] instead. That keeps a
  /// lock, revocation, or expired lease from becoming a fresh authorization.
  bool bindRememberedPeerAfterUnboundRevision({
    required UserProfile profile,
    required ProfileScope scope,
    required String peerFingerprint,
    required String sessionId,
  }) {
    final sameUnlockedScope =
        _profileId == scope.profileId &&
        _generation == scope.dataGeneration &&
        _sessionEpoch == scope.sessionEpoch &&
        profile.id == _profileId &&
        profile.isEnabled;
    final revisionChanged =
        _authorizationRevision != null &&
        _authorizationRevision != profile.authorizationRevision;
    if (!sameUnlockedScope || !revisionChanged || _peerSessions.isNotEmpty) {
      return false;
    }
    authorize(profile, scope);
    return bindAuthenticatedPeer(
      peerFingerprint: peerFingerprint,
      sessionId: sessionId,
      scope: scope,
      currentProfile: profile,
    );
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
