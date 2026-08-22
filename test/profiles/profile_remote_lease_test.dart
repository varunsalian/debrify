import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 13);
  const peer = 'peer-fingerprint';
  const session = 'session-id';

  UserProfile profile({int revision = 1, DateTime? disabledAt}) => UserProfile(
    id: 'profile-one',
    name: 'Profile',
    role: UserProfileRole.member,
    policy: ProfilePolicy.defaultsFor(UserProfileRole.member),
    authorizationRevision: revision,
    lifecycle: UserProfileLifecycle.active,
    visibleDataGeneration: 1,
    setupComplete: true,
    pinResetRequired: false,
    hasPin: false,
    lockOnResume: false,
    createdAt: now,
    updatedAt: now,
    disabledAt: disabledAt,
  );

  setUp(ProfileRemoteLease.instance.revoke);
  tearDown(() {
    ProfileRemoteLease.instance
      ..revoke()
      ..debugSetClock(null);
  });

  test('lease binds profile generation, epoch, revision, and feature', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );

    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteTransfer,
        scope,
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        ProfileScope(
          profileId: original.id,
          dataGeneration: 1,
          sessionEpoch: 6,
        ),
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isFalse,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: original,
        peerFingerprint: 'peer-two',
        sessionId: session,
      ),
      isFalse,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: 'different-session',
      ),
      isFalse,
    );
  });

  test('revision change or disablement invalidates an issued lease', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    ProfileRemoteLease.instance.bindAuthenticatedPeer(
      peerFingerprint: peer,
      sessionId: session,
      scope: scope,
      currentProfile: original,
    );

    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: profile(revision: 2),
        peerFingerprint: peer,
        sessionId: session,
      ),
      isFalse,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: profile(disabledAt: now),
        peerFingerprint: peer,
        sessionId: session,
      ),
      isFalse,
    );
  });

  test('live remembered peer can renew after an ordinary revision', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    ProfileRemoteLease.instance.bindAuthenticatedPeer(
      peerFingerprint: peer,
      sessionId: session,
      scope: scope,
      currentProfile: original,
    );

    final updated = profile(revision: 2);
    expect(
      ProfileRemoteLease.instance.renewRememberedPeerAfterRevision(
        profile: updated,
        scope: scope,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteTransfer,
        scope,
        currentProfile: updated,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
  });

  test('live remembered peer can renew after revision and reconnect', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );

    final updated = profile(revision: 2);
    expect(
      ProfileRemoteLease.instance.renewRememberedPeerAfterRevision(
        profile: updated,
        scope: scope,
        peerFingerprint: peer,
        sessionId: 'replacement-session',
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteTransfer,
        scope,
        currentProfile: updated,
        peerFingerprint: peer,
        sessionId: 'replacement-session',
      ),
      isTrue,
    );
  });

  test('revision reconnect cannot adopt another peer lease', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );

    expect(
      ProfileRemoteLease.instance.renewRememberedPeerAfterRevision(
        profile: profile(revision: 2),
        scope: scope,
        peerFingerprint: 'different-peer',
        sessionId: 'replacement-session',
      ),
      isFalse,
    );
  });

  test('remembered peer can bind after a pre-admission revision', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);

    final updated = profile(revision: 2);
    expect(
      ProfileRemoteLease.instance.bindRememberedPeerAfterUnboundRevision(
        profile: updated,
        scope: scope,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteTransfer,
        scope,
        currentProfile: updated,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
  });

  test('pre-admission revision bind requires the same unlocked scope', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    ProfileRemoteLease.instance.revoke();

    expect(
      ProfileRemoteLease.instance.bindRememberedPeerAfterUnboundRevision(
        profile: profile(revision: 2),
        scope: scope,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isFalse,
    );
  });

  test('pre-admission path cannot replace an issued peer lease', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );

    expect(
      ProfileRemoteLease.instance.bindRememberedPeerAfterUnboundRevision(
        profile: profile(revision: 2),
        scope: scope,
        peerFingerprint: 'different-peer',
        sessionId: 'different-session',
      ),
      isFalse,
    );
  });

  test('expired remembered peer cannot renew after a revision', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.debugSetClock(() => now);
    ProfileRemoteLease.instance.authorize(original, scope);
    ProfileRemoteLease.instance.bindAuthenticatedPeer(
      peerFingerprint: peer,
      sessionId: session,
      scope: scope,
      currentProfile: original,
    );
    ProfileRemoteLease.instance.debugSetClock(
      () => now.add(const Duration(minutes: 16)),
    );

    expect(
      ProfileRemoteLease.instance.renewRememberedPeerAfterRevision(
        profile: profile(revision: 2),
        scope: scope,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isFalse,
    );
  });

  test('approved mutation rebinds only the importing peer to new revision', () {
    final original = profile();
    final updated = profile(revision: 2);
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.reauthorizeApprovedPeer(
        profile: updated,
        scope: scope,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteTransfer,
        scope,
        currentProfile: updated,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteTransfer,
        scope,
        currentProfile: updated,
        peerFingerprint: 'different-peer',
        sessionId: 'different-session',
      ),
      isFalse,
      reason: 'revision refresh must not revive unrelated peers',
    );
  });

  test('explicit lock revokes every peer session', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );
    ProfileRemoteLease.instance.revoke();
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isFalse,
    );
  });

  test('expired peer cannot self-renew during inbound routing', () {
    var clock = now;
    ProfileRemoteLease.instance.debugSetClock(() => clock);
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );
    clock = now.add(const Duration(minutes: 15, milliseconds: 1));

    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isFalse,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isFalse,
    );
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: 'replacement-session',
        scope: scope,
        currentProfile: original,
      ),
      isFalse,
      reason: 'A new transport session cannot bypass the peer tombstone',
    );
  });

  test('live peer lease follows an authenticated reconnect session', () {
    var clock = now;
    ProfileRemoteLease.instance.debugSetClock(() => clock);
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: session,
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );
    clock = now.add(const Duration(minutes: 5));
    expect(
      ProfileRemoteLease.instance.bindAuthenticatedPeer(
        peerFingerprint: peer,
        sessionId: 'replacement-session',
        scope: scope,
        currentProfile: original,
      ),
      isTrue,
    );
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: 'replacement-session',
      ),
      isTrue,
    );
  });

  test('chunk admission does not consume the interactive peer budget', () {
    final original = profile();
    final scope = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 5,
    );
    ProfileRemoteLease.instance.authorize(original, scope);
    ProfileRemoteLease.instance.bindAuthenticatedPeer(
      peerFingerprint: peer,
      sessionId: session,
      scope: scope,
      currentProfile: original,
    );
    for (var index = 0; index < 500; index++) {
      expect(
        ProfileRemoteLease.instance.allows(
          ProfileFeature.remoteTransfer,
          scope,
          currentProfile: original,
          peerFingerprint: peer,
          sessionId: session,
          rateLimit: false,
        ),
        isTrue,
      );
    }
    expect(
      ProfileRemoteLease.instance.allows(
        ProfileFeature.remoteControl,
        scope,
        currentProfile: original,
        peerFingerprint: peer,
        sessionId: session,
      ),
      isTrue,
    );
  });
}
