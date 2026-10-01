import 'package:debrify/features/home/application/home_hero_providers.dart';
import 'package:debrify/features/home/application/home_hero_trailer_loader.dart';
import 'package:debrify/features/home/data/home_hero_trailer_repository.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);
  for (final retire in ['dispose', 'recompute', 'profile']) {
    test('$retire keeps trailer requests scoped to their view lifetime', () {
      fakeAsync((time) {
        var reads = 0;
        final published = <String>[];
        final repo = HomeHeroTrailerRepository(
          readPreferences: (current) async {
            reads++;
            return current() ? MetadataPreferences() : null;
          },
          selectTrailers: (_, _, _) async => [
            const MetadataTrailer(
              key: 'yt',
              title: '',
              language: '',
              type: '',
              official: false,
            ),
          ],
          fetchDetails: (_, _) async => null,
          resolveYoutube: (_) async =>
              const YoutubeResolvedStreams(playUrl: 'video'),
          resolveImdb: (_) async => null,
        );
        final container = ProviderContainer(
          overrides: [
            homeHeroTrailerRepositoryProvider.overrideWithValue(repo),
          ],
        );
        HomeCatalogSession session() => HomeCatalogSession(
          owner: ProfileSessionMemory.captureOwner(),
          viewIdentity: Object(),
        );
        void schedule(HomeHeroTrailerLoader loader, String label) =>
            loader.schedule(
              const StremioMeta(id: 'tt1', type: 'movie', name: 'Title'),
              delay: Duration.zero,
              isCurrent: () => true,
              reset: () {},
              begin: () => true,
              publish: (_) => published.add(label),
              fail: () => fail('unexpected failure'),
            );
        final key = session();
        final first = container.listen(
          homeHeroTrailerLoaderProvider(key),
          (_, _) {},
        );
        final second = container.listen(
          homeHeroTrailerLoaderProvider(session()),
          (_, _) {},
        );
        expect(first.read(), isNot(same(second.read())));
        expect(reads, 0);
        final old = first.read();
        schedule(old, 'old');
        schedule(second.read(), 'second');
        switch (retire) {
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(homeHeroTrailerLoaderProvider(key));
            final replacement = first.read();
            expect(replacement, isNot(same(old)));
            schedule(replacement, 'new');
          case 'profile':
            ProfileRuntime.promoteLegacyToCommitted(
              ProfileScope(
                profileId: 'next',
                dataGeneration: 1,
                sessionEpoch: 1,
              ),
            );
        }
        time.elapse(Duration.zero);
        if (retire == 'recompute') {
          expect(published, unorderedEquals(['second', 'new']));
          expect(reads, 2);
        } else {
          expect(published, isEmpty);
          expect(reads, 0);
        }
        if (retire != 'dispose') container.dispose();
        time.flushMicrotasks();
        expect(time.nonPeriodicTimerCount, 0);
      });
    });
  }
}
