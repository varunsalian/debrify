import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('role ceilings cannot be raised by stored policy', () {
    final policy = ProfilePolicy(
      schemaVersion: ProfilePolicy.currentSchemaVersion,
      enabled: ProfileFeature.values.toSet(),
    );

    expect(
      policy.allows(UserProfileRole.member, ProfileFeature.manageProfiles),
      isFalse,
    );
    expect(
      policy.allows(UserProfileRole.child, ProfileFeature.manageConnections),
      isFalse,
    );
    expect(
      policy.allows(UserProfileRole.admin, ProfileFeature.manageProfiles),
      isTrue,
    );
  });

  test('full editor policy enables every role-allowed feature', () {
    final unconstrained = ProfilePolicy(enabled: ProfileFeature.values.toSet());
    for (final role in UserProfileRole.values) {
      final full = ProfilePolicy.allAllowedFor(role);
      for (final feature in ProfileFeature.values) {
        expect(
          full.enabled.contains(feature),
          unconstrained.allows(role, feature),
          reason: '${role.name}.${feature.name}',
        );
      }
    }

    expect(
      ProfilePolicy.allAllowedFor(
        UserProfileRole.child,
      ).enabled.contains(ProfileFeature.downloads),
      isTrue,
    );
    expect(
      ProfilePolicy.allAllowedFor(
        UserProfileRole.child,
      ).enabled.contains(ProfileFeature.allowAdultContent),
      isFalse,
    );
  });

  test('unknown policy versions and malformed JSON fail closed', () {
    final unknown = ProfilePolicy.decode(
      '{"version":99,"enabled":["cloud"]}',
      UserProfileRole.admin,
    );
    final malformed = ProfilePolicy.decode('{', UserProfileRole.admin);

    expect(unknown.enabled, isEmpty);
    expect(malformed.enabled, isEmpty);
  });

  test('policy round trips without granting unknown features', () {
    final original = ProfilePolicy.defaultsFor(UserProfileRole.member);
    final decoded = ProfilePolicy.decode(
      original.encode(),
      UserProfileRole.member,
    );

    expect(decoded.schemaVersion, ProfilePolicy.currentSchemaVersion);
    expect(decoded.enabled, original.enabled);
  });

  // The questionnaire preset matrix (mock v6): surfaces differ per role,
  // operations stay on so hiding a page never severs the plumbing.
  test('v2 defaults follow the questionnaire preset matrix', () {
    final admin = ProfilePolicy.defaultsFor(UserProfileRole.admin).enabled;
    final member = ProfilePolicy.defaultsFor(UserProfileRole.member).enabled;
    final child = ProfilePolicy.defaultsFor(UserProfileRole.child).enabled;

    expect(admin.contains(ProfileFeature.keywordSearch), isTrue);
    expect(admin.contains(ProfileFeature.cloudFiles), isTrue);

    expect(member.contains(ProfileFeature.keywordSearch), isTrue);
    expect(
      member.contains(ProfileFeature.cloudFiles),
      isFalse,
      reason: "a shared account's file list is the owner's viewing history",
    );
    // Default, not ceiling: an admin can grant the Cloud pages back.
    expect(
      ProfilePolicy(
        enabled: {ProfileFeature.cloudFiles},
      ).allows(UserProfileRole.member, ProfileFeature.cloudFiles),
      isTrue,
    );

    for (final off in <ProfileFeature>[
      ProfileFeature.keywordSearch,
      ProfileFeature.cloudFiles,
      ProfileFeature.addonsAndEngines,
      ProfileFeature.stremioTv,
      ProfileFeature.iptv,
      ProfileFeature.youtube,
      ProfileFeature.remoteControl,
    ]) {
      expect(child.contains(off), isFalse, reason: 'child ${off.name}');
    }
    // The operations that keep a Kid's curated playback working — and
    // Debrify TV, whose channels ARE keyword operations under the hood.
    for (final on in <ProfileFeature>[
      ProfileFeature.cloud,
      ProfileFeature.torrentSearch,
      ProfileFeature.debrifyTv,
      ProfileFeature.trackersAndDiscovery,
    ]) {
      expect(child.contains(on), isTrue, reason: 'child ${on.name}');
    }
    // addonUse is the v3 addon-read operation: EVERY role keeps it, or Home
    // shelves and catalog search die with "Manage own sources" off.
    for (final role in UserProfileRole.values) {
      expect(
        ProfilePolicy.defaultsFor(role).enabled.contains(
          ProfileFeature.addonUse,
        ),
        isTrue,
        reason: '${role.name} addonUse',
      );
    }
  });

  test('v1 policies upgrade at decode: surfaces seeded from role defaults', () {
    // A faithful v1 payload: everything that existed then, per old defaults.
    String v1(Iterable<ProfileFeature> enabled) =>
        '{"schemaVersion":1,"enabled":[${enabled.map((f) => '"${f.name}"').join(',')}]}';
    final v1Features = ProfileFeature.values
        .where(
          (f) =>
              f != ProfileFeature.keywordSearch &&
              f != ProfileFeature.cloudFiles &&
              f != ProfileFeature.addonUse,
        )
        .toList();

    final admin = ProfilePolicy.decode(
      v1(v1Features),
      UserProfileRole.admin,
    );
    expect(admin.schemaVersion, ProfilePolicy.currentSchemaVersion);
    expect(admin.enabled.contains(ProfileFeature.keywordSearch), isTrue);
    expect(admin.enabled.contains(ProfileFeature.cloudFiles), isTrue);

    final member = ProfilePolicy.decode(
      v1(v1Features.where((f) => f != ProfileFeature.manageProfiles)),
      UserProfileRole.member,
    );
    expect(member.enabled.contains(ProfileFeature.keywordSearch), isTrue);
    expect(member.enabled.contains(ProfileFeature.cloudFiles), isFalse);

    final child = ProfilePolicy.decode(
      v1(<ProfileFeature>[ProfileFeature.debrifyTv, ProfileFeature.cloud]),
      UserProfileRole.child,
    );
    expect(child.enabled.contains(ProfileFeature.keywordSearch), isFalse);
    expect(child.enabled.contains(ProfileFeature.cloudFiles), isFalse);
    // Upgrade never touches v1-era bits: this "customized" child keeps
    // exactly what its stored policy said.
    expect(child.enabled.contains(ProfileFeature.debrifyTv), isTrue);
    expect(child.enabled.contains(ProfileFeature.cloud), isTrue);
    expect(child.enabled.contains(ProfileFeature.iptv), isFalse);
    // …but every upgrade seeds the addon-read operation.
    expect(child.enabled.contains(ProfileFeature.addonUse), isTrue);
  });

  test('v2 policies upgrade at decode: addonUse seeded for every role', () {
    // A faithful v2 payload — the kid the questionnaire wrote on 2026-08-16,
    // before addonUse existed. Decoding it must grant the addon-read
    // operation or its Home shelves break, while the v2-era bits (no
    // keywordSearch, no iptv) stay exactly as stored.
    final kidV2 = ProfilePolicy.decode(
      '{"schemaVersion":2,"enabled":["cloud","torrentSearch","debrifyTv",'
      '"trackersAndDiscovery","externalPlayers","incomingLinks"]}',
      UserProfileRole.child,
    );
    expect(kidV2.schemaVersion, ProfilePolicy.currentSchemaVersion);
    expect(kidV2.enabled.contains(ProfileFeature.addonUse), isTrue);
    expect(kidV2.enabled.contains(ProfileFeature.keywordSearch), isFalse);
    expect(kidV2.enabled.contains(ProfileFeature.iptv), isFalse);
    expect(kidV2.enabled.contains(ProfileFeature.debrifyTv), isTrue);
  });
}
