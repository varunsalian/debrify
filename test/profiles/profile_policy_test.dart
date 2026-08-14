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
}
