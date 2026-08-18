import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/utils/stremio_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest normalization preserves query authentication', () {
    expect(
      normalizeStremioManifestUri(
        'https://addon.invalid/config/manifest.json?token=secret',
      ).toString(),
      'https://addon.invalid/config/manifest.json?token=secret',
    );
    expect(
      normalizeStremioManifestUri(
        'stremio://addon.invalid/config?token=secret',
      ).toString(),
      'https://addon.invalid/config/manifest.json?token=secret',
    );
  });

  test('manifest model derives an authenticated addon root', () {
    final addon = StremioAddon.fromManifest(const <String, dynamic>{
      'id': 'test.addon',
      'name': 'Test addon',
      'resources': <String>['subtitles'],
    }, 'https://addon.invalid/config/manifest.json?token=secret');

    expect(addon.baseUrl, 'https://addon.invalid/config?token=secret');
    expect(
      buildStremioResourceUri(addon.baseUrl, const <String>[
        'subtitles',
        'series',
        'tt123:1:2.json',
      ]).toString(),
      'https://addon.invalid/config/subtitles/series/tt123:1:2.json?token=secret',
    );
  });

  test('resource construction does not double-encode IDs', () {
    expect(
      buildStremioResourceUri(
        'https://addon.invalid/root?token=secret',
        const <String>['stream', 'tv', 'channel%2Fone.json'],
      ).toString(),
      'https://addon.invalid/root/stream/tv/channel%2Fone.json?token=secret',
    );
    expect(
      buildStremioResourceUri(
        'https://addon.invalid/root?token=secret',
        const <String>['catalog', 'movie', 'search=rock%26roll.json'],
      ).toString(),
      'https://addon.invalid/root/catalog/movie/search=rock%26roll.json?token=secret',
    );
  });
}
