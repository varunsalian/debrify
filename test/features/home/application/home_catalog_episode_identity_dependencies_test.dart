import 'package:debrify/features/home/application/home_catalog_episode_identity_dependencies.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);
  final addon = StremioAddon(
    id: 'fixture',
    name: 'Fixture',
    baseUrl: 'https://fixture.invalid',
    manifestUrl: 'https://fixture.invalid/manifest.json',
    addedAt: DateTime.utc(2026),
  );
  const selection = AdvancedSearchSelection(
    imdbId: 'tt123',
    isSeries: true,
    title: 'Fixture',
    season: 1,
    episode: 1,
  );
  const item = StremioMeta(id: 'tt123', type: 'series', name: 'Fixture');

  test(
    'production canonical lookup preserves ordinary selection after factory disposal',
    () async {
      final container = ProviderContainer.test();
      final resolver = container.read(
        homeCatalogEpisodeIdentityProvider(ProfileSessionMemory.captureOwner()),
      );
      await container.pump();
      expect(
        await resolver.resolve(selection, item, addon, isCurrent: () => true),
        same(selection),
      );
    },
  );

  test(
    'retained production resolver rejects retired profile before metadata access',
    () async {
      final container = ProviderContainer.test();
      final resolver = container.read(
        homeCatalogEpisodeIdentityProvider(ProfileSessionMemory.captureOwner()),
      );
      ProfileSessionMemory.clearAll();
      expect(
        await resolver.resolve(
          selection,
          const StremioMeta(id: 'custom', type: 'series', name: 'Custom'),
          addon,
          isCurrent: () => true,
        ),
        isNull,
      );
    },
  );
}
