import 'package:debrify/features/search/application/keyword_filter.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../keyword_torrent_fixture.dart';

List<Torrent> filter(
  List<Torrent> torrents, {
  bool cachedOnly = false,
  Map<String, List<String>> cache = const {},
  Map<String, int> directCounts = const {},
  Map<String, int> torrentCounts = const {},
  Set<String> selectedDirect = const {},
  Set<String> selectedTorrent = const {},
  String? tab,
  TorrentFilterState filters = const TorrentFilterState.empty(),
}) => filterKeywordResults(
  torrents,
  cachedOnly: cachedOnly,
  cache: cache,
  directCounts: directCounts,
  torrentCounts: torrentCounts,
  selectedDirect: selectedDirect,
  selectedTorrent: selectedTorrent,
  sourceTab: tab,
  filters: filters,
);

void main() {
  test('disabled cached-only preserves uncached results in engine order', () {
    final input = List<Torrent>.unmodifiable([
      keywordTorrent('z'),
      keywordTorrent('a'),
    ]);
    final result = filter(input);
    expect(result, input);
    result.clear();
    expect(input, hasLength(2));
  });

  test('cached-only requires TB, not PM, and matches lowercase badge keys', () {
    final tb = keywordTorrent('TB', hash: 'ABC');
    final pm = keywordTorrent('PM', hash: 'pm');
    final absent = keywordTorrent('none');
    expect(
      filter(
        [pm, tb, absent],
        cachedOnly: true,
        cache: const {
          'abc': ['TB', 'PM'],
          'pm': ['PM'],
        },
      ),
      [tb],
    );
  });

  test('cache lookup preserves whitespace exactly like the badge', () {
    final torrent = keywordTorrent('Spaced hash', hash: ' ABC ');
    expect(
      isKeywordTorboxCached(torrent, {
        'abc': ['TB'],
      }),
      isFalse,
    );
    expect(
      isKeywordTorboxCached(torrent, {
        ' abc ': ['TB'],
      }),
      isTrue,
    );
  });

  test(
    'hashless download links survive; direct/external type alone is no exemption',
    () {
      final link = keywordTorrent(
        'Download',
        hasRealHash: false,
        torrentUrl: 'https://example.test/a.torrent',
      );
      final noUrl = keywordTorrent('No URL', hasRealHash: false);
      final hashAndUrl = keywordTorrent(
        'Hash and URL',
        torrentUrl: 'https://example.test/b.torrent',
      );
      final direct = keywordTorrent('Direct', type: StreamType.directUrl);
      final external = keywordTorrent('External', type: StreamType.externalUrl);
      expect(
        filter([link, noUrl, hashAndUrl, direct, external], cachedOnly: true),
        [link],
      );
    },
  );

  test('empty provider groups impose no constraint', () {
    final direct = keywordTorrent(
      'Direct',
      type: StreamType.directUrl,
      source: 'd',
    );
    final torrent = keywordTorrent('Torrent', source: 't');
    expect(filter([direct, torrent]), [direct, torrent]);
    expect(filter([direct, torrent], torrentCounts: {'t': 1}), [direct]);
    expect(filter([direct, torrent], directCounts: {'d': 1}), [torrent]);
  });

  test('direct/external selections are independent of torrent selections', () {
    final direct = keywordTorrent(
      'Direct',
      type: StreamType.directUrl,
      source: 'same',
    );
    final external = keywordTorrent(
      'External',
      type: StreamType.externalUrl,
      source: 'same',
    );
    final torrent = keywordTorrent('Torrent', source: 'same');
    expect(
      filter(
        [direct, external, torrent],
        directCounts: {'same': 2},
        torrentCounts: {'same': 1},
        selectedTorrent: {'same'},
      ),
      [torrent],
    );
    expect(
      filter(
        [direct, external, torrent],
        directCounts: {'same': 2},
        torrentCounts: {'same': 1},
        selectedDirect: {'same'},
      ),
      [direct, external],
    );
  });

  test(
    'source tab narrows provider choices and cannot resurrect an unticked source',
    () {
      final a = keywordTorrent('a', source: 'a');
      final b = keywordTorrent('b', source: 'b');
      expect(
        filter(
          [a, b],
          torrentCounts: {'a': 1, 'b': 1},
          selectedTorrent: {'a'},
          tab: 'b',
        ),
        isEmpty,
      );
      expect(
        filter(
          [a, b],
          torrentCounts: {'a': 1, 'b': 1},
          selectedTorrent: {'a', 'b'},
          tab: 'b',
        ),
        [b],
      );
    },
  );

  test('empty source shares the unknown provider and tab bucket', () {
    final unknown = keywordTorrent('No source');
    expect(
      filter(
        [unknown],
        torrentCounts: {'unknown': 1},
        selectedTorrent: {'unknown'},
        tab: 'unknown',
      ),
      [unknown],
    );
  });

  test('cached, provider, tab and existing attribute facets compose', () {
    final good = keywordTorrent(
      'Movie.1080p.WEB-DL.ENG',
      source: 'a',
      hash: 'good',
    );
    final wrongQuality = keywordTorrent(
      'Movie.2160p.WEB-DL.ENG',
      source: 'a',
      hash: '4k',
    );
    final wrongProvider = keywordTorrent(
      'Movie.1080p.WEB-DL.ENG',
      source: 'b',
      hash: 'b',
    );
    final uncached = keywordTorrent(
      'Movie.1080p.WEB-DL.ENG',
      source: 'a',
      hash: 'uncached',
    );
    expect(
      filter(
        [wrongQuality, good, wrongProvider, uncached],
        cachedOnly: true,
        cache: {
          'good': ['TB'],
          '4k': ['TB'],
          'b': ['TB'],
        },
        torrentCounts: {'a': 3, 'b': 1},
        selectedTorrent: {'a', 'b'},
        tab: 'a',
        filters: TorrentFilterState(
          qualities: {QualityTier.fullHd},
          ripSources: {RipSourceCategory.web},
          languages: {AudioLanguage.english},
        ),
      ),
      [good],
    );
  });
}
