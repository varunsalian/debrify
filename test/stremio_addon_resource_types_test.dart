import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Stremio manifest may declare `resources` as plain strings or as objects
/// carrying their own `types`/`idPrefixes`. Addons using the object form
/// routinely leave the top-level `types` empty, so they parse into an addon
/// that declares no types at all.
///
/// That is fine — empty means "unrestricted" — but the stream query used to
/// read it as "serves nothing" for movie and series specifically, and dropped
/// the addon without ever making a request. To the user that looks like the
/// addon is incompatible with the app.
void main() {
  group('StremioAddon.fromManifest with object-form resources', () {
    // Verbatim from https://stremthru.elfhosted.com/stremio/torz/manifest.json
    // (2026-08-04) — the addon a user reported as not searching.
    const torzManifest = '''
{"id":"com.elfhosted.stremthru.torz","name":"StremThru Torz",
 "description":"Stremio Addon to access crowdsourced Torz","version":"0.103.2",
 "resources":[{"name":"stream","types":["movie","series","anime"],
 "idPrefixes":["tt","kitsu:","mal:"]}],
 "types":[],"catalogs":[],
 "behaviorHints":{"configurable":true,"configurationRequired":true}}
''';

    test('is recognised as a stream addon that restricts nothing', () {
      final addon = StremioAddon.fromManifest(
        jsonDecode(torzManifest) as Map<String, dynamic>,
        'https://stremthru.elfhosted.com/stremio/torz/manifest.json',
      );

      expect(addon.supportsStreams, isTrue);
      // Empty on purpose: hoisting the per-resource types would narrow the
      // queries that read empty as "unrestricted" (see fromManifest).
      expect(addon.types, isEmpty);
      // And an absent top-level idPrefixes must not be read as a restriction.
      expect(addon.supportsContentId('tt0111161'), isTrue);
    });

    test('keeps the plain-string resource form working', () {
      final addon = StremioAddon.fromManifest(
        <String, dynamic>{
          'id': 'org.example.streams',
          'name': 'Example',
          'resources': <dynamic>['stream', 'meta'],
          'types': <dynamic>['movie', 'series'],
        },
        'https://example.com/manifest.json',
      );

      expect(addon.resources, <String>['stream', 'meta']);
      expect(addon.types, <String>['movie', 'series']);
      expect(addon.supportsMovies, isTrue);
      expect(addon.supportsSeries, isTrue);
    });

    test('a declared top-level types is still honoured alongside objects', () {
      final addon = StremioAddon.fromManifest(
        <String, dynamic>{
          'id': 'org.example.movies',
          'name': 'Movies Only',
          'resources': <dynamic>[
            <String, dynamic>{
              'name': 'stream',
              'types': <dynamic>['movie', 'series'],
            },
          ],
          'types': <dynamic>['movie'],
        },
        'https://example.com/manifest.json',
      );

      expect(addon.resources, <String>['stream']);
      expect(addon.types, <String>['movie']);
      expect(addon.supportsSeries, isFalse);
    });
  });
}
