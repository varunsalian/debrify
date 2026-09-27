import 'dart:async';
import 'package:debrify/features/home/data/home_episode_artwork_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'three workers retain input order and omit missing or empty stills',
    () async {
      final pending = <String, Completer<String?>>{};
      var active = 0;
      var peak = 0;
      final repository = HomeEpisodeArtworkRepository(({
        required imdbId,
        required season,
        required episode,
      }) async {
        expect(season, 2);
        expect(episode, int.parse(imdbId));
        active++;
        if (active > peak) peak = active;
        final response = pending[imdbId] = Completer<String?>();
        final result = await response.future;
        active--;
        return result;
      });
      final result = repository.read({
        for (var i = 1; i <= 5; i++) '$i': (season: 2, episode: i),
      }, isCurrent: () => true);
      expect(pending.keys, ['1', '2', '3']);
      pending['3']!.complete('third');
      await Future<void>.delayed(Duration.zero);
      expect(pending.keys, ['1', '2', '3', '4']);
      pending['2']!.complete(null);
      await Future<void>.delayed(Duration.zero);
      pending['5']!.complete('');
      pending['4']!.complete('fourth');
      pending['1']!.complete('first');
      final accepted = (await result)!;
      expect(peak, 3);
      expect(accepted.keys, ['1', '3', '4']);
      expect(accepted, {'1': 'first', '3': 'third', '4': 'fourth'});
      expect(() => accepted.clear(), throwsUnsupportedError);
    },
  );
  test('retirement stops queued reads and discards completed stills', () async {
    final pending = <Completer<String?>>[];
    var current = true;
    final repository = HomeEpisodeArtworkRepository(({
      required imdbId,
      required season,
      required episode,
    }) {
      final response = Completer<String?>();
      pending.add(response);
      return response.future;
    });
    final result = repository.read({
      for (var i = 0; i < 8; i++) '$i': (season: 1, episode: 1),
    }, isCurrent: () => current);
    expect(pending.length, 3);
    current = false;
    for (final response in pending) {
      response.complete('old');
    }
    expect(await result, isNull);
    expect(pending.length, 3);
    expect(
      await repository.read({
        'late': (season: 1, episode: 1),
      }, isCurrent: () => false),
      isNull,
    );
    expect(pending.length, 3);
  });
  test(
    'empty inputs do not resolve artwork; active reader errors propagate',
    () async {
      var reads = 0;
      final repository = HomeEpisodeArtworkRepository(({
        required imdbId,
        required season,
        required episode,
      }) async {
        reads++;
        throw StateError('reader');
      });
      expect(await repository.read({}, isCurrent: () => true), isEmpty);
      expect(reads, 0);
      await expectLater(
        repository.read({'id': (season: 1, episode: 2)}, isCurrent: () => true),
        throwsStateError,
      );
    },
  );
}
