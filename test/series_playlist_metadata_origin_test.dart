import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Origin PREP only. Actual old public methods; no host/native or fake clock.
// These eight cases do not claim saved-mapping misses, escaping image/title
// casts, concurrent completion order, in-flight deduplication or retry timing.
const _tv = 'https://api.tvmaze.com';
const _cinemeta = 'https://v3-cinemeta.strem.io';

class _PlannedGet {
  _PlannedGet(this.url, this.respond);
  final String url;
  final FutureOr<http.Response> Function() respond;
}

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value), status, headers: {'content-type': 'application/json'},
);

class _Fixture {
  final planned = <_PlannedGet>[];
  final observed = <String>[];
  final unknown = <String>[];
  final clients = <_FixtureClient>[];
  int consumed = 0;

  void get(String url, Object response, [int status = 200]) =>
      planned.add(_PlannedGet(url, () => _json(response, status)));

  http.Client newClient() {
    final client = _FixtureClient(this);
    clients.add(client);
    return client;
  }

  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final description = '${request.method} ${request.url}';
    observed.add(description);
    if (consumed >= planned.length ||
        request.method != 'GET' ||
        request.url.toString() != planned[consumed].url ||
        request.headers['accept'] != 'application/json') {
      unknown.add('$description headers=${request.headers}');
      // Production can swallow this. The separate final ledger still fails.
      throw SocketException('Unplanned origin request: $description');
    }
    final step = planned[consumed++];
    final bytes = await request.finalize().toBytes();
    if (bytes.isNotEmpty) {
      unknown.add('$description unexpected request body');
      throw const SocketException('Unexpected origin request body');
    }
    final response = await step.respond();
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes), response.statusCode,
      headers: response.headers, request: request,
    );
  }
}

class _FixtureClient extends http.BaseClient {
  _FixtureClient(this.fixture);
  final _Fixture fixture;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (closed) {
      fixture.unknown.add('send on closed fixture client');
      throw StateError('send on closed fixture client');
    }
    return fixture.send(request);
  }

  @override
  void close() { closed = true; }
}

Future<void> _withFixture(Future<void> Function(_Fixture) body) async {
  final fixture = _Fixture();
  final failures = <(Object, StackTrace)>[];
  void record(Object error, StackTrace stack) {
    failures.add((error, stack));
    debugPrintSynchronously('SERIES_ORIGIN_FAILURE $error\n$stack');
  }

  await http.runWithClient(() async {
    try {
      SharedPreferences.setMockInitialValues({});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      EpisodeInfoService.dispose();
      await TVMazeService.clearCache();
      MovieMetadataService.clearCache();
      // clearCache does not reset currentAvailability. Use its real probe.
      fixture.get('$_tv/shows/1', {'id': 1});
      await TVMazeService.refreshAvailability();
      expect(TVMazeService.currentAvailability, isTrue);
      expect(fixture.observed, ['GET $_tv/shows/1']);
      await body(fixture);
    } catch (error, stack) {
      record(error, stack);
    } finally {
      // Body owns releasing/joining held requests before these resource resets.
      try {
        EpisodeInfoService.dispose();
        await TVMazeService.clearCache();
        MovieMetadataService.clearCache();
      } catch (error, stack) {
        record(error, stack);
      }
      try {
        expect(fixture.unknown, isEmpty);
        expect(fixture.consumed, fixture.planned.length,
            reason: 'Every explicitly planned request must occur');
        expect(fixture.clients.every((client) => client.closed), isTrue,
            reason: 'Top-level http.get closes each fresh client');
      } catch (error, stack) {
        record(error, stack);
      } finally {
        ProfileRuntime.debugReset();
        SharedPreferences.setMockInitialValues({});
      }
    }
  }, fixture.newClient);
  if (failures.isNotEmpty) {
    Error.throwWithStackTrace(failures.first.$1, failures.first.$2);
  }
}

SeriesPlaylist _series() => SeriesPlaylist.fromPlaylistEntries([
  const PlaylistEntry(url: 'https://fixture.invalid/1', title: 'Origin.Show.S01E01.mkv'),
  const PlaylistEntry(url: 'https://fixture.invalid/2', title: 'Origin.Show.S01E02.mkv'),
], collectionTitle: 'Origin Show', forceSeries: true);

SeriesPlaylist _movies() => SeriesPlaylist.fromPlaylistEntries([
  const PlaylistEntry(url: 'https://fixture.invalid/a', title: 'Origin.Film.2020.mkv'),
  const PlaylistEntry(url: 'https://fixture.invalid/b', title: 'Second.Film.2021.mkv'),
], forceSeries: false);

Map<String, dynamic> _show(int id) => {
  'id': id, 'name': 'Origin Show', 'externals': {'imdb': 'tt9999999'},
  'image': {'original': 'https://images.invalid/show', 'medium': 'medium'},
  'genres': ['Drama'], 'language': 'English',
  'network': {'name': 'Fixture', 'country': {'name': 'Fixture Country'}},
};

Map<String, dynamic> _episode(int number, {String airdate = '2020-01-02'}) => {
  'season': 1, 'number': number, 'name': 'Episode $number',
  'airdate': airdate, 'summary': '<p>Plot $number</p>', 'runtime': 42,
  'image': {'medium': 'https://images.invalid/$number'},
  'rating': {'average': 8.5},
};

Map<String, dynamic> _movie(String title, String year, String id) => {
  'metas': [{'name': title, 'year': year, 'id': id}],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved mapping wins over parameter lookup and mutates existing episodes', () async {
    await _withFixture((fixture) async {
      final playlist = _series();
      final episodes = List<SeriesEpisode>.of(playlist.allEpisodes);
      final season = playlist.seasons.single;
      final item = <String, dynamic>{'rdTorrentId': 'origin-mapped'};
      await PlaybackProgressStore.saveTVMazeSeriesMapping(
        playlistItem: item, tvmazeShowId: 4101, showName: 'Mapped',
      );
      fixture.get('$_tv/shows/4101', _show(4101));
      fixture.get('$_tv/shows/4101/episodes', [_episode(1), _episode(3)]);
      await playlist.fetchEpisodeInfo(playlistItem: item, imdbId: 'tt1111111');
      expect(playlist.seasons.single, same(season));
      for (var i = 0; i < episodes.length; i++) {
        expect(playlist.allEpisodes[i], same(episodes[i]));
      }
      expect(episodes[0].episodeInfo!.title, 'Episode 1');
      // Nonempty bulk response missing episode2 does NOT trigger per-item HTTP.
      expect(episodes[1].episodeInfo, isNull);
      expect(playlist.imdbId, 'tt1111111');
      expect(playlist.tvmazeShowId, 4101);
      expect(playlist.tvmazeShowName, 'Origin Show');
      expect(playlist.showPosterUrl, 'https://images.invalid/show');
      expect(playlist.fullTvmazeEpisodes.map((e) => e['number']), [1, 3]);
    });
  });

  test('missing parameter lookup falls back to title then bulk episodes', () async {
    await _withFixture((fixture) async {
      final playlist = _series();
      fixture.get('$_tv/lookup/shows?imdb=tt2222222', {}, 404);
      fixture.get('$_tv/search/shows?q=origin%20show', [{'score': 1, 'show': _show(4102)}]);
      fixture.get('$_tv/shows/4102/episodes', [_episode(1), _episode(2)]);
      await playlist.fetchEpisodeInfo(imdbId: 'tt2222222');
      expect(playlist.tvmazeShowId, 4102);
      expect(playlist.imdbId, 'tt2222222');
      expect(playlist.allEpisodes.map((e) => e.episodeInfo!.title), ['Episode 1', 'Episode 2']);
    });
  });

  test('tt parameter replaces existing field before first suspension', () async {
    await _withFixture((fixture) async {
      final playlist = _series()..imdbId = 'tt0000000';
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      fixture.planned.add(_PlannedGet('$_tv/lookup/shows?imdb=tt3333333', () {
        requested.complete();
        return response.future;
      }));
      fixture.get('$_tv/shows/4103/episodes', [_episode(1), _episode(2)]);
      final operation = playlist.fetchEpisodeInfo(imdbId: 'tt3333333');
      Object? primary;
      StackTrace? primaryStack;
      try {
        expect(playlist.imdbId, 'tt3333333'); // No await before this assertion.
        await requested.future.timeout(const Duration(seconds: 2));
        expect(playlist.allEpisodes.first.episodeInfo, isNull);
      } catch (error, stack) {
        primary = error;
        primaryStack = stack;
      } finally {
        response.complete(_json(_show(4103)));
        try {
          await operation;
        } catch (error, stack) {
          debugPrintSynchronously('SERIES_ORIGIN_HELD_JOIN $error\n$stack');
          primary ??= error;
          primaryStack ??= stack;
        }
      }
      if (primary != null) Error.throwWithStackTrace(primary, primaryStack!);
      expect(playlist.imdbId, 'tt3333333');
      expect(playlist.allEpisodes.first.episodeInfo!.title, 'Episode 1');
    });
  });

  test('single episode lookup returns metadata without mutating playlist entries', () async {
    await _withFixture((fixture) async {
      final playlist = _series();
      final original = playlist.allEpisodes.first;
      fixture.get('$_tv/search/shows?q=Origin%20Show', [{'show': _show(4104)}]);
      fixture.get('$_tv/shows/4104/episodes', [_episode(1)]);
      final result = await playlist.getEpisodeInfoForEpisode('Origin Show', 1, 1);
      expect(result!.title, 'Episode 1');
      expect(result.plot, 'Plot 1');
      expect(result.genres, ['Drama']);
      expect(result.country, 'Fixture Country');
      expect(result.runtime, 42);
      expect(playlist.allEpisodes.first, same(original));
      expect(original.episodeInfo, isNull);
      expect(playlist.fullTvmazeEpisodes, isEmpty);
    });
  });

  test('movie wrapper targets zero and per-index cache survives service reset', () async {
    await _withFixture((fixture) async {
      final playlist = _movies();
      fixture.get('$_cinemeta/manifest.json', {});
      fixture.get('$_cinemeta/catalog/movie/top/search=origin%20film.json', _movie('Origin Film', '2020', 'tt4444444'));
      await playlist.fetchMovieMetadata();
      expect(playlist.getImdbIdForIndex(0), 'tt4444444');
      fixture.get('$_cinemeta/catalog/movie/top/search=second%20film.json', _movie('Second Film', '2021', 'tt5555555'));
      expect(await playlist.fetchMovieMetadataForIndex(1), 'tt5555555');
      expect(playlist.imdbId, 'tt4444444'); // Serial first success only.
      expect(playlist.getImdbIdForIndex(1), 'tt5555555');
      MovieMetadataService.clearCache();
      final before = fixture.observed.length;
      expect(await playlist.fetchMovieMetadataForIndex(1), 'tt5555555');
      expect(fixture.observed.length, before);
      expect(playlist.getImdbIdForIndex(99), 'tt4444444'); // Getter shared fallback.
    });
  });

  test('ineligible series and movie branches perform no method HTTP', () async {
    await _withFixture((fixture) async {
      final before = fixture.observed.length;
      final movies = _movies();
      await movies.fetchEpisodeInfo(imdbId: 'tt6666666');
      expect(movies.imdbId, isNull);
      expect(await movies.fetchMovieMetadataForIndex(-1), isNull);
      expect(await movies.fetchMovieMetadataForIndex(99), isNull);
      final series = _series()..imdbId = 'tt7777777';
      expect(await series.fetchMovieMetadataForIndex(-1), 'tt7777777');
      final noYear = SeriesPlaylist.fromPlaylistEntries([
        const PlaylistEntry(url: 'https://fixture.invalid/no-year', title: 'Undated.Film.mkv'),
      ], forceSeries: false);
      expect(await noYear.fetchMovieMetadataForIndex(0), isNull);
      expect(fixture.observed.length, before);
    });
  });

  test('numbered episode conversion errors are swallowed by the actual methods', () async {
    await _withFixture((fixture) async {
      final playlist = _series();
      final original = playlist.allEpisodes.first;
      const prior = EpisodeInfo(title: 'Prior');
      original.episodeInfo = prior;
      fixture.get('$_tv/lookup/shows?imdb=tt8888888', _show(4107));
      fixture.get('$_tv/shows/4107/episodes', [_episode(1, airdate: '')]);
      await playlist.fetchEpisodeInfo(imdbId: 'tt8888888');
      expect(original.episodeInfo, same(prior));
      expect(playlist.tvmazeShowId, 4107); // Earlier mutations are not rolled back.
      expect(playlist.fullTvmazeEpisodes, hasLength(1));
      fixture.get('$_tv/search/shows?q=Origin%20Show', [{'show': _show(4107)}]);
      expect(await playlist.getEpisodeInfoForEpisode('Origin Show', 1, 1), isNull);
      // Episode list is legitimately cached; no generic model-cache claim.
    });
  });

  test('movie transport failure returns null without manufacturing metadata', () async {
    await _withFixture((fixture) async {
      final playlist = _movies();
      fixture.get('$_cinemeta/manifest.json', {});
      fixture.planned.add(_PlannedGet('$_cinemeta/catalog/movie/top/search=origin%20film.json', () {
        throw const SocketException('planned Cinemeta failure');
      }));
      expect(await playlist.fetchMovieMetadataForIndex(0), isNull);
      expect(playlist.imdbId, isNull);
      expect(playlist.getImdbIdForIndex(0), isNull);
      // Service handles the transport error; does not pin model outer-catch.
    });
  });

  // Additive cache contract pins below; the original eight cases are unchanged.
  test('successful index cache precedes bounds and belongs to one playlist', () async {
    await _withFixture((fixture) async {
      final first = _movies();
      final other = _movies();
      fixture.get('$_cinemeta/manifest.json', {});
      fixture.get('$_cinemeta/catalog/movie/top/search=second%20film.json',
          _movie('Second Film', '2021', 'tt9100001'));
      expect(await first.fetchMovieMetadataForIndex(1), 'tt9100001');
      MovieMetadataService.clearCache();
      first.allEpisodes.removeLast(); // Public mutable list makes index1 invalid.
      expect(first.allEpisodes, hasLength(1));
      final before = fixture.observed.length;
      expect(await first.fetchMovieMetadataForIndex(1), 'tt9100001');
      expect(fixture.observed.length, before);
      // Same title/index on a different playlist must not reuse first's cache.
      fixture.get('$_cinemeta/manifest.json', {});
      fixture.get('$_cinemeta/catalog/movie/top/search=second%20film.json',
          _movie('Second Film', '2021', 'tt9100002'));
      expect(await other.fetchMovieMetadataForIndex(1), 'tt9100002');
      expect(await first.fetchMovieMetadataForIndex(1), 'tt9100001');
      expect(first.imdbId, 'tt9100001');
      expect(other.imdbId, 'tt9100002');
    });
  });

  test('successful movie lookup preserves nonnull empty shared IMDb', () async {
    await _withFixture((fixture) async {
      final playlist = _movies()..imdbId = '';
      fixture.get('$_cinemeta/manifest.json', {});
      fixture.get('$_cinemeta/catalog/movie/top/search=origin%20film.json',
          _movie('Origin Film', '2020', 'tt9200001'));
      expect(await playlist.fetchMovieMetadataForIndex(0), 'tt9200001');
      expect(playlist.imdbId, '');
      expect(playlist.getImdbIdForIndex(0), 'tt9200001');
      expect(playlist.getImdbIdForIndex(99), '');
    });
  });

  test('distinct indices retain their IDs while first successful completion wins shared', () async {
    await _withFixture((fixture) async {
      await _primeMovieAvailability(fixture);
      final playlist = _movies();
      final first = _HeldMovieGet(fixture,
          '$_cinemeta/catalog/movie/top/search=origin%20film.json',
          _movie('Origin Film', '2020', 'tt9300001'));
      final second = _HeldMovieGet(fixture,
          '$_cinemeta/catalog/movie/top/search=second%20film.json',
          _movie('Second Film', '2021', 'tt9300002'));
      final firstOperation = playlist.fetchMovieMetadataForIndex(0);
      Future<String?>? secondOperation;
      Object? primary;
      StackTrace? primaryStack;
      try {
        await first.entered.future.timeout(const Duration(seconds: 2));
        secondOperation = playlist.fetchMovieMetadataForIndex(1);
        await second.entered.future.timeout(const Duration(seconds: 2));
        expect(playlist.imdbId, isNull);
        second.release();
        expect(await secondOperation, 'tt9300002');
        expect(playlist.imdbId, 'tt9300002');
        expect(first.response.isCompleted, isFalse);
        first.release();
        expect(await firstOperation, 'tt9300001');
        expect(playlist.getImdbIdForIndex(0), 'tt9300001');
        expect(playlist.getImdbIdForIndex(1), 'tt9300002');
        expect(playlist.imdbId, 'tt9300002');
      } catch (error, stack) {
        primary = error;
        primaryStack = stack;
      } finally {
        await _releaseAndJoinPair(first, second, firstOperation, secondOperation,
            primary, primaryStack);
      }
    });
  });

  test('same index permits two overlapping requests and last completion overwrites index', () async {
    await _withFixture((fixture) async {
      await _primeMovieAvailability(fixture);
      final playlist = _movies();
      final first = _HeldMovieGet(fixture,
          '$_cinemeta/catalog/movie/top/search=origin%20film.json',
          _movie('Origin Film', '2020', 'tt9400001'));
      final second = _HeldMovieGet(fixture,
          '$_cinemeta/catalog/movie/top/search=origin%20film.json',
          _movie('Origin Film', '2020', 'tt9400002'));
      final firstOperation = playlist.fetchMovieMetadataForIndex(0);
      Future<String?>? secondOperation;
      Object? primary;
      StackTrace? primaryStack;
      try {
        await first.entered.future.timeout(const Duration(seconds: 2));
        secondOperation = playlist.fetchMovieMetadataForIndex(0);
        await second.entered.future.timeout(const Duration(seconds: 2));
        expect(first.response.isCompleted, isFalse);
        expect(playlist.imdbId, isNull);
        second.release();
        expect(await secondOperation, 'tt9400002');
        expect(playlist.getImdbIdForIndex(0), 'tt9400002');
        expect(playlist.imdbId, 'tt9400002');
        first.release();
        expect(await firstOperation, 'tt9400001');
        expect(playlist.getImdbIdForIndex(0), 'tt9400001');
        expect(playlist.imdbId, 'tt9400002');
      } catch (error, stack) {
        primary = error;
        primaryStack = stack;
      } finally {
        await _releaseAndJoinPair(first, second, firstOperation, secondOperation,
            primary, primaryStack);
      }
    });
  });

  test('unsuccessful movie result is not stored in the model index cache', () async {
    await _withFixture((fixture) async {
      final playlist = _movies();
      fixture.get('$_cinemeta/manifest.json', {});
      fixture.get('$_cinemeta/catalog/movie/top/search=origin%20film.json', {'metas': []});
      expect(await playlist.fetchMovieMetadataForIndex(0), isNull);
      expect(playlist.imdbId, isNull);
      // Discard the downstream service's negative cache before probing the model.
      MovieMetadataService.clearCache();
      fixture.get('$_cinemeta/manifest.json', {});
      fixture.get('$_cinemeta/catalog/movie/top/search=origin%20film.json',
          _movie('Origin Film', '2020', 'tt9500001'));
      expect(await playlist.fetchMovieMetadataForIndex(0), 'tt9500001');
      expect(playlist.getImdbIdForIndex(0), 'tt9500001');
      expect(playlist.imdbId, 'tt9500001');
    });
  });
}

// Minimal additive transport helpers; no model injection or completion observer.
Future<void> _primeMovieAvailability(_Fixture fixture) async {
  fixture.get('$_cinemeta/manifest.json', {});
  fixture.get('$_cinemeta/catalog/movie/top/search=warmup%20film.json',
      _movie('Warmup Film', '2019', 'tt9000000'));
  // Existing public service call primes only availability and a distinct key.
  // It avoids racing two incidental availability probes in the overlap cases.
  final warmup = await MovieMetadataService.lookupMovie('Warmup Film', 2019);
  expect(warmup!.imdbId, 'tt9000000');
}

class _HeldMovieGet {
  _HeldMovieGet(_Fixture fixture, String url, this.payload) {
    fixture.planned.add(_PlannedGet(url, () {
      entered.complete();
      return response.future;
    }));
  }
  final Object payload;
  final entered = Completer<void>();
  final response = Completer<http.Response>();

  void release() {
    if (!response.isCompleted) response.complete(_json(payload));
  }
}

Future<void> _releaseAndJoinPair(
  _HeldMovieGet first,
  _HeldMovieGet second,
  Future<String?> firstOperation,
  Future<String?>? secondOperation,
  Object? primary,
  StackTrace? primaryStack,
) async {
  // Release BOTH before either join, including when entry assertion failed.
  first.release();
  second.release();
  try {
    await firstOperation;
  } catch (error, stack) {
    debugPrintSynchronously('SERIES_ORIGIN_FIRST_JOIN $error\n$stack');
    primary ??= error;
    primaryStack ??= stack;
  }
  try {
    if (secondOperation != null) await secondOperation;
  } catch (error, stack) {
    debugPrintSynchronously('SERIES_ORIGIN_SECOND_JOIN $error\n$stack');
    primary ??= error;
    primaryStack ??= stack;
  }
  if (primary != null) Error.throwWithStackTrace(primary, primaryStack!);
}
