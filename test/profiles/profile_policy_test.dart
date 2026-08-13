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
