import 'package:debrify/features/discover/application/discover_card_settings_controller.dart';
import 'package:debrify/features/discover/application/discover_card_settings_dependencies.dart';
import 'package:debrify/features/discover/models/discover_card_settings.dart';
import 'package:debrify/services/discover_prefs.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    DiscoverPrefs.debugReset();
    SharedPreferences.setMockInitialValues({
      'discover_show_type_tags': false,
      'discover_show_ratings': false,
      'discover_show_titles': false,
    });
  });
  tearDown(() {
    DiscoverPrefs.debugReset();
    ProfileRuntime.debugReset();
  });

  test(
    'reader uses the warmed cache without warming or persisting itself',
    () async {
      final key = (
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      );
      final container = ProviderContainer.test();
      container.listen(discoverCardSettingsProvider(key), (_, _) {});
      final controller = container.read(
        discoverCardSettingsProvider(key).notifier,
      );
      expect(controller.current, defaultDiscoverCardSettings);
      await DiscoverPrefs.warmUp();
      expect(controller.current, defaultDiscoverCardSettings);
      expect(controller.refresh(isCurrent: () => true), isTrue);
      expect(controller.current, (
        showTypeTags: false,
        showRatings: false,
        showTitles: false,
      ));
      await DiscoverPrefs.setShowTitles(true);
      expect(controller.readSnapshot(isCurrent: () => true).showTitles, isTrue);
      expect(controller.current.showTitles, isFalse);
    },
  );

  for (final retire in ['dispose', 'handoff']) {
    test(
      'default reader rejects $retire even if its callback was retained',
      () {
        final key = (
          owner: ProfileSessionMemory.captureOwner(),
          viewIdentity: Object(),
        );
        final container = ProviderContainer.test();
        final reader = container
            .listen(discoverCardSettingsReaderProvider(key), (_, _) {})
            .read();
        expect(reader(), defaultDiscoverCardSettings);
        if (retire == 'dispose') {
          container.dispose();
        } else {
          ProfileSessionMemory.clearAll();
        }
        expect(reader(), isNull);
      },
    );
  }
}
