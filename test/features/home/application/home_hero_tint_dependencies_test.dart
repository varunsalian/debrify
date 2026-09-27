import 'dart:async';
import 'dart:ui';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/features/home/application/home_hero_tint_dependencies.dart';
import 'package:debrify/features/home/application/home_hero_tint_loader.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
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
  for (final retire in ['dispose', 'recompute', 'profile', 'handoff']) {
    test(
      '$retire rejects outgoing tint results with independent view owners',
      () async {
        final response = Completer<Color?>();
        var reads = 0;
        final published = <String>[];
        final container = ProviderContainer(
          overrides: [
            homeHeroTintResolverProvider.overrideWithValue((_) {
              reads++;
              return response.future;
            }),
          ],
        );
        HomeCatalogSession session() => HomeCatalogSession(
          owner: ProfileSessionMemory.captureOwner(),
          viewIdentity: Object(),
        );
        void load(HomeHeroTintLoader preview, String label) => preview.load(
          const StremioMeta(
            id: 'A',
            type: 'movie',
            name: 'A',
            poster: 'poster',
          ),
          isCurrent: () => true,
          publish: (_) => published.add(label),
        );
        final key = session();
        final first = container.listen(
          homeHeroTintLoaderProvider(key),
          (_, _) {},
        );
        final second = container.listen(
          homeHeroTintLoaderProvider(session()),
          (_, _) {},
        );
        expect(first.read(), isNot(same(second.read())));
        expect(reads, 0);
        final old = first.read();
        load(old, 'old');
        load(second.read(), 'second');
        await Future<void>.delayed(const Duration(milliseconds: 140));
        switch (retire) {
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(homeHeroTintLoaderProvider(key));
            final replacement = first.read();
            expect(replacement, isNot(same(old)));
            load(replacement, 'new');
            await Future<void>.delayed(const Duration(milliseconds: 140));
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
        response.complete(const Color(0xFFFF0000));
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
