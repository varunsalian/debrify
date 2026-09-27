import 'dart:async';
import 'package:debrify/features/home/application/home_default_view_dependencies.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/features/search/models/search_mode.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final retire in ['profile', 'dispose', 'recompute']) {
    test(
      '$retire closes pending view work; construction performs no read',
      () async {
        var reads = 0;
        final response = Completer<String?>();
        final container = ProviderContainer.test(
          overrides: [
            homeDefaultViewReaderProvider.overrideWithValue(() {
              reads++;
              return response.future;
            }),
          ],
        );
        final session = HomeCatalogSession(
          owner: ProfileSessionMemory.captureOwner(),
          viewIdentity: Object(),
        );
        final subscription = container.listen(
          homeDefaultViewProvider(session),
          (_, _) {},
        );
        final operation = subscription.read();
        expect(reads, 0);
        final pending = operation.load(
          isTelevision: false,
          isHome: true,
          isCurrent: () => true,
          select: (_) => fail('retired selection'),
        );
        switch (retire) {
          case 'profile':
            ProfileSessionMemory.clearAll();
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(homeDefaultViewProvider(session));
            subscription.read();
        }
        response.complete('catalog');
        await pending;
        if (retire == 'recompute') {
          final selected = <SearchMode>[];
          await subscription.read().load(
            isTelevision: true,
            isHome: true,
            isCurrent: () => true,
            select: selected.add,
          );
          expect(selected, [SearchMode.catalog]);
          expect(subscription.read(), isNot(same(operation)));
        }
        expect(reads, 1);
      },
    );
  }
}
