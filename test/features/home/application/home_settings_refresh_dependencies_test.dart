import 'package:debrify/features/home/application/home_settings_refresh_dependencies.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'home_settings_refresh_test.dart' show RefreshProbe;

void main() {
  for (final reason in ['profile', 'dispose', 'recompute']) {
    test('$reason retires the scoped workflow', () async {
      final container = ProviderContainer.test();
      final key = HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      );
      final subscription = container.listen(
        homeSettingsRefreshProvider(key),
        (_, _) {},
      );
      final probe = RefreshProbe(subscription.read())..blocked = 'appearance';
      final pending = probe.run();
      await probe.arrived.future;
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'dispose':
          container.dispose();
        case 'recompute':
          container.invalidate(homeSettingsRefreshProvider(key));
          subscription.read();
      }
      probe.barrier.complete();
      await pending;
      expect(probe.events, ['appearance']);
      if (reason == 'recompute') {
        final replacement = RefreshProbe(subscription.read());
        await replacement.run();
        expect(replacement.events.last, 'apply');
      }
    });
  }
}
