import 'package:debrify/features/home/application/home_hero_providers.dart';
import 'package:debrify/features/home/data/home_hero_metadata_repository.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
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
    test('$retire retires pending work with independent view lifetimes', () {
      fakeAsync((time) {
        const item = StremioMeta(id: 'tt1', type: 'movie', name: 'Title');
        var fetches = 0;
        final accepted = <String>[];
        final container = ProviderContainer(
          overrides: [
            homeHeroMetadataRepositoryProvider.overrideWithValue(
              HomeHeroMetadataRepository(
                readPreferences: (current) async =>
                    current() ? MetadataPreferences() : null,
                fetchDetails: (_, _) async {
                  fetches++;
                  return item;
                },
                present: (item, _, _) async => MetadataPresentation(item),
              ),
            ),
          ],
        );
        HomeCatalogSession session() => HomeCatalogSession(
          owner: ProfileSessionMemory.captureOwner(),
          viewIdentity: Object(),
        );
        final key = session();
        final first = container.listen(
          homeHeroMetadataLoaderProvider(key),
          (_, _) {},
        );
        final second = container.listen(
          homeHeroMetadataLoaderProvider(session()),
          (_, _) {},
        );
        expect(first.read(), isNot(same(second.read())));
        expect(fetches, 0);
        final old = first.read();
        old.load(
          item,
          isCurrent: () => true,
          onResolved: (_) => accepted.add('old'),
        );
        second.read().load(
          item,
          isCurrent: () => true,
          onResolved: (_) => accepted.add('second'),
        );
        time.flushMicrotasks();
        switch (retire) {
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(homeHeroMetadataLoaderProvider(key));
            final replacement = first.read();
            expect(replacement, isNot(same(old)));
            replacement.load(
              item,
              isCurrent: () => true,
              onResolved: (_) => accepted.add('new'),
            );
          case 'profile':
            ProfileRuntime.promoteLegacyToCommitted(
              ProfileScope(
                profileId: 'next',
                dataGeneration: 1,
                sessionEpoch: 1,
              ),
            );
        }
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 140));
        if (retire == 'recompute') {
          expect(accepted, unorderedEquals(['second', 'new']));
          expect(fetches, 2);
        } else {
          expect(accepted, isEmpty);
          expect(fetches, 0);
        }
        if (retire != 'dispose') container.dispose();
      });
    });
  }
}
