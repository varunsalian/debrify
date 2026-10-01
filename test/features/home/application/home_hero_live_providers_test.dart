import 'dart:async';
import 'package:debrify/features/home/application/home_hero_providers.dart';
import 'package:debrify/features/home/application/home_hero_live_preview.dart';
import 'package:debrify/features/home/data/home_hero_live_repository.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);
  for (final retire in ['dispose', 'recompute', 'profile', 'handoff']) {
    test(
      '$retire rejects outgoing live candidates with independent view owners',
      () async {
        final response = Completer<List<StremioIptvCandidate>>();
        var reads = 0;
        final published = <String>[];
        final container = ProviderContainer(
          overrides: [
            homeHeroLiveRepositoryProvider.overrideWithValue(
              HomeHeroLiveRepository(
                isAddonChannel: (_) => true,
                resolveCandidates: (_) {
                  reads++;
                  return response.future;
                },
                invalidate: (_) => fail('no playback failure'),
              ),
            ),
          ],
        );
        HomeCatalogSession session() => HomeCatalogSession(
          owner: ProfileSessionMemory.captureOwner(),
          viewIdentity: Object(),
        );
        void load(HomeHeroLivePreview preview, String label) => preview.load(
          'addon:a',
          isCurrent: () => true,
          prepare: () {},
          publish: (_) => published.add(label),
        );
        final key = session();
        final first = container.listen(
          homeHeroLivePreviewProvider(key),
          (_, _) {},
        );
        final second = container.listen(
          homeHeroLivePreviewProvider(session()),
          (_, _) {},
        );
        expect(first.read(), isNot(same(second.read())));
        expect(reads, 0);
        final old = first.read();
        load(old, 'old');
        load(second.read(), 'second');
        switch (retire) {
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(homeHeroLivePreviewProvider(key));
            final replacement = first.read();
            expect(replacement, isNot(same(old)));
            load(replacement, 'new');
          case 'profile':
            ProfileRuntime.promoteLegacyToCommitted(
              ProfileScope(
                profileId: 'next',
                dataGeneration: 1,
                sessionEpoch: 1,
              ),
            );
          case 'handoff':
            ProfileSessionMemory.clearAll();
        }
        response.complete([
          const StremioIptvCandidate(url: 'video', label: ''),
        ]);
        await Future<void>.delayed(Duration.zero);
        expect(
          published,
          retire == 'recompute' ? unorderedEquals(['second', 'new']) : isEmpty,
        );
        expect(reads, retire == 'recompute' ? 3 : 2);
        if (retire != 'dispose') container.dispose();
      },
    );
  }
}
