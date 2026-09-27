import 'package:debrify/features/home/models/home_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy codec preserves unknown provider fields and detaches both directions',
    () {
      final nested = <String, dynamic>{
        'files': [
          1,
          'two',
          null,
          {'url': 'URL', 'enabled': true},
        ],
      };
      final input = <String, dynamic>{
        'title': '',
        'posterUrl': 'poster',
        'kind': 'single',
        'provider': 'torbox',
        'extension': nested,
      };
      final item = HomePlaylistItem.fromLegacy(input, dedupeKey: 'key');
      expect(item.title, '');
      expect(item.posterUrl, 'poster');
      expect(item.isCollection, isFalse);
      expect(item.dedupeKey, 'key');
      expect(item.toLegacyItem(), input);
      final copy = item.toLegacyItem();
      (copy['extension']['files'] as List).clear();
      copy['title'] = 'changed';
      (nested['files'] as List).clear();
      input.clear();
      expect(item.toLegacyItem()['extension']['files'], [
        1,
        'two',
        null,
        {'url': 'URL', 'enabled': true},
      ]);
      expect(item.title, '');
      expect(item.toLegacyItem()['title'], '');
      final fallback = HomePlaylistItem.fromLegacy({}, dedupeKey: 'empty');
      expect(fallback.title, 'Unknown');
      expect(fallback.isCollection, isTrue);
      expect(fallback.toLegacyItem(), isEmpty);
    },
  );

  test(
    'non-JSON or malformed typed fields are rejected at the legacy codec',
    () {
      expect(
        () => HomePlaylistItem.fromLegacy({'bad': Object()}, dedupeKey: 'a'),
        throwsFormatException,
      );
      expect(
        () => HomePlaylistItem.fromLegacy({'title': 4}, dedupeKey: 'a'),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test(
    'progress uses truncated millisecond numbers, clamping and presence independently',
    () {
      final item = HomePlaylistItem.fromLegacy({}, dedupeKey: 'a');
      final cases = <(Map<String, dynamic>, double?)>[
        ({}, null),
        ({'position': 5, 'duration': 10}, null),
        ({'positionMs': 1, 'durationMs': 0}, null),
        ({'positionMs': 1, 'durationMs': -2}, null),
        ({'positionMs': -2, 'durationMs': 10}, 0),
        ({'positionMs': 15, 'durationMs': 10}, 1),
        ({'positionMs': 5.9, 'durationMs': 10.9}, 0.5),
        ({'durationMs': 10}, null),
      ];
      for (final (raw, fraction) in cases) {
        final favorites = {'a'};
        final progress = {'a': HomePlaylistProgress.fromLegacy(raw)};
        final items = [item];
        final state = HomePlaylist(
          items: items,
          favorites: favorites,
          progress: progress,
        );
        expect(state.progressFor(item), fraction);
        expect(state.hasProgress(item), isTrue);
        expect(state.isFavorite(item), isTrue);
        favorites.clear();
        progress.clear();
        items.clear();
        expect(state.items.single, same(item));
        expect(state.hasProgress(item), isTrue);
        expect(state.isFavorite(item), isTrue);
        expect(state.items.clear, throwsUnsupportedError);
        expect(state.progress.clear, throwsUnsupportedError);
        expect(state.favorites.clear, throwsUnsupportedError);
      }
      const empty = HomePlaylist.empty();
      expect(empty.hasProgress(item), isFalse);
      expect(empty.progressFor(item), isNull);
      expect(empty.isFavorite(item), isFalse);
    },
  );
}
