import 'dart:io';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scope produces stable generation-aware keys and paths', () {
    final scope = ProfileScope(
      profileId: 'profile-abc_123',
      dataGeneration: 7,
      sessionEpoch: 4,
    );

    expect(scope.preferencePrefix, 'p.profile-abc_123.g.7.');
    expect(scope.preferenceKey('theme'), 'p.profile-abc_123.g.7.theme');
    expect(
      scope.file(Directory('/tmp/root'), 'db/catalog.sqlite').path,
      contains('profiles/profile-abc_123/g/7/data/db/catalog.sqlite'),
    );
  });

  test('scope rejects unsafe identifiers and traversal', () {
    expect(
      () => ProfileScope(
        profileId: '../admin',
        dataGeneration: 1,
        sessionEpoch: 0,
      ),
      throwsArgumentError,
    );
    final scope = ProfileScope(
      profileId: 'safe',
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    expect(
      () => scope.file(Directory('/tmp/root'), '../escape'),
      throwsArgumentError,
    );
  });
}
