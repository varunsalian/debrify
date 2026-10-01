import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retired factory cannot enter the legacy artwork service', () async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    addTearDown(ProfileRuntime.debugReset);
    final container = ProviderContainer.test();
    final key = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homeEpisodeArtworkRepositoryProvider(key), (_, _) {});
    final repository = container.read(
      homeEpisodeArtworkRepositoryProvider(key),
    );
    ProfileSessionMemory.clearAll();
    // No storage/platform/network fixture: rejected work must return before
    // entering the default service, even if a caller supplied a permissive guard.
    expect(
      await repository.read({
        'tt1234567': (season: 1, episode: 1),
      }, isCurrent: () => true),
      isEmpty,
    );
  });
}
