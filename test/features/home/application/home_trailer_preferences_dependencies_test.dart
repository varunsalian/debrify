import 'package:debrify/features/home/application/home_trailer_preferences_dependencies.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'default adapter keeps Home and Detail audio keys distinct and storage clamping intact',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      SharedPreferences.setMockInitialValues({
        'home_hero_trailer_enabled': false,
        'home_hero_trailer_audio_enabled': false,
        'home_hero_trailer_volume': 85,
        'detail_trailer_audio_enabled': true,
        'detail_trailer_volume': 32,
      });
      final container = ProviderContainer.test();
      final repo = container.read(homeTrailerPreferencesRepositoryProvider);
      expect(await repo.read(useHomeAudio: true), (
        enabled: false,
        volume: 0.0,
      ));
      expect(await repo.read(useHomeAudio: false), (
        enabled: false,
        volume: 32.0,
      ));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('detail_trailer_volume', 999);
      expect((await repo.read(useHomeAudio: false)).volume, 100);
      expect(prefs.getInt('home_hero_trailer_volume'), 85);
    },
  );
}
