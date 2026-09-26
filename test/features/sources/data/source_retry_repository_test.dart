import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_source_search_services.dart';

AdvancedSearchSelection selection({
  bool series = true,
  String? type,
  bool custom = false,
  String? video,
}) => AdvancedSearchSelection(
  imdbId: 'tt-fixture',
  title: 'Fixture',
  isSeries: series,
  season: 3,
  episode: 7,
  contentType: type,
  stremioAddonKey: custom ? 'origin' : null,
  stremioCatalogId: custom ? 'catalog' : null,
  stremioVideoId: video,
);

void main() {
  for (final kind in ['movie', 'series', 'channel']) {
    test(
      '$kind retry preserves exact configuration, coordinates, timeout and order',
      () async {
        final fake = FakeSourceSearchServices();
        final pending = fake.repository.retry(
          selection(
            series: kind != 'movie',
            type: kind == 'channel' ? kind : null,
          ),
          'specific-configuration',
          shouldContinue: () => true,
        );
        expect(fake.calls, ['retry']);
        expect(fake.arguments, {
          'retryKey': 'specific-configuration',
          'type': kind,
          'id': 'tt-fixture',
          'season': 3,
          'episode': 7,
          'timeout': StremioService.manualRetryTimeout,
          'preserve': true,
          'video': null,
        });
        fake.retryResult.complete([]);
        final rows = (await pending)!;
        expect(rows, isEmpty);
        expect(() => rows.add(Torrent.fromJson({})), throwsUnsupportedError);
      },
    );
  }

  test(
    'explicit custom video is trimmed and does not perform metadata lookup',
    () async {
      final fake = FakeSourceSearchServices();
      final pending = fake.repository.retry(
        selection(custom: true, video: ' arbitrary/id '),
        'retry-config',
        shouldContinue: () => true,
      );
      expect(fake.calls, ['retry']);
      expect(fake.arguments['video'], 'arbitrary/id');
      fake.retryResult.complete([]);
      await pending;
    },
  );

  for (final found in [false, true]) {
    test('custom resolution controls retry dispatch: found=$found', () async {
      final fake = FakeSourceSearchServices();
      final pending = fake.repository.retry(
        selection(custom: true),
        'retry-config',
        shouldContinue: () => true,
      );
      expect(fake.calls, ['resolve']);
      expect(fake.arguments['resolveAddon'], 'origin');
      expect(fake.arguments['resolveCatalog'], 'catalog');
      fake.video.complete(found ? 'exact-id' : null);
      await Future<void>.delayed(Duration.zero);
      if (found) {
        expect(fake.calls, ['resolve', 'retry']);
        expect(fake.arguments['video'], 'exact-id');
        fake.retryResult.complete([]);
        expect(await pending, isEmpty);
      } else {
        expect(await pending, isNull);
        expect(fake.calls, ['resolve']);
      }
    });
  }

  for (final retire in ['query', 'profile']) {
    test('$retire during resolution prevents addon request', () async {
      final fake = FakeSourceSearchServices();
      var active = true;
      final pending = fake.repository.retry(
        selection(custom: true),
        'retry-config',
        shouldContinue: () => active,
      );
      if (retire == 'query') {
        active = false;
      } else {
        ProfileSessionMemory.clearAll();
      }
      fake.video.complete('exact');
      expect(await pending, isNull);
      expect(fake.calls, ['resolve']);
    });
    test('$retire suppresses a late request failure', () async {
      final fake = FakeSourceSearchServices();
      var active = true;
      final pending = fake.repository.retry(
        selection(),
        'retry-config',
        shouldContinue: () => active,
      );
      if (retire == 'query') {
        active = false;
      } else {
        ProfileSessionMemory.clearAll();
      }
      fake.retryResult.completeError(StateError('fixture'));
      expect(await pending, isNull);
    });
  }
}
