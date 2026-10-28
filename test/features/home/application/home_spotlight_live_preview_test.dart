import 'dart:async';
import 'package:debrify/features/home/application/home_spotlight_live_preview.dart';
import 'package:debrify/features/home/data/home_hero_live_repository.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'initial synchronous publication stays quiet but an async result requests a rebuild',
    () async {
      final pending = Completer<List<StremioIptvCandidate>>();
      final values = <(String?, bool)>[];
      var reads = 0;
      final preview = HomeSpotlightLivePreview(
        repository: HomeHeroLiveRepository(
          isAddonChannel: (key) => key.startsWith('addon:'),
          resolveCandidates: (_) {
            reads++;
            return pending.future;
          },
          invalidate: (_) => fail('no failure'),
        ),
        isOwnerCurrent: () => true,
      );
      void load(String key, {bool series = false}) => preview.resolve(
        channelKey: key,
        isSeries: series,
        isCurrent: () => true,
        notify: false,
        publish: (url, notify) => values.add((url, notify)),
      );
      load('direct');
      expect(values, [('direct', false)]);
      load('addon:series', series: true);
      expect(values.last, (null, false));
      expect(reads, 0);
      load('addon:a');
      expect(values.last, (null, false));
      expect(reads, 1);
      pending.complete([
        const StremioIptvCandidate(url: 'resolved', label: ''),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(values.last, ('resolved', true));
      preview.dispose();
    },
  );

  test(
    'empty results stay blank and retired owners cannot invalidate cached candidates',
    () async {
      var owner = true;
      var empty = true;
      var reads = 0;
      final published = <String?>[];
      final invalidations = <String>[];
      final preview = HomeSpotlightLivePreview(
        repository: HomeHeroLiveRepository(
          isAddonChannel: (_) => true,
          resolveCandidates: (_) async {
            reads++;
            return empty
                ? []
                : [const StremioIptvCandidate(url: 'only', label: '')];
          },
          invalidate: invalidations.add,
        ),
        isOwnerCurrent: () => owner,
      );
      void load() => preview.resolve(
        channelKey: 'addon:a',
        isSeries: false,
        isCurrent: () => true,
        publish: (url, _) => published.add(url),
      );
      load();
      await Future<void>.delayed(Duration.zero);
      expect(published, [null]);
      empty = false;
      load();
      await Future<void>.delayed(Duration.zero);
      expect(published, [null, null, 'only']);
      owner = false;
      preview.playbackFailed(
        currentUrl: 'only',
        channelKey: 'addon:a',
        publish: published.add,
      );
      load();
      // A retired owner clears the old stream without a new lookup.
      expect(published, [null, null, 'only', null]);
      expect(invalidations, isEmpty);
      expect(reads, 2);
      preview.dispose();
    },
  );

  test(
    'synchronous disposal while clearing stops resolution from starting',
    () {
      late HomeSpotlightLivePreview preview;
      preview = HomeSpotlightLivePreview(
        repository: HomeHeroLiveRepository(
          isAddonChannel: (_) => true,
          resolveCandidates: (_) => throw StateError('retired before lookup'),
          invalidate: (_) => fail('no failure'),
        ),
        isOwnerCurrent: () => true,
      );
      preview.resolve(
        channelKey: 'addon:a',
        isSeries: false,
        isCurrent: () => true,
        publish: (_, _) => preview.dispose(),
      );
    },
  );
}
