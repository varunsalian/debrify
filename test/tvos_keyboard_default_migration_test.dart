import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Apple TV Debrify keyboard default migration', () {
    test(
      'fresh Apple TV profiles start with the Debrify keyboard disabled',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        expect(
          await TvDisplayStorage.getTvKeyboardEnabled(tvOs: true),
          isFalse,
        );
      },
    );

    test('overrides an explicit value from an older build once', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_keyboard_enabled': true,
      });

      expect(await TvDisplayStorage.getTvKeyboardEnabled(tvOs: true), isFalse);
    });

    test('a user can enable it again after the migration', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_keyboard_enabled': true,
      });
      expect(await TvDisplayStorage.getTvKeyboardEnabled(tvOs: true), isFalse);

      await TvDisplayStorage.setTvKeyboardEnabled(true);

      expect(await TvDisplayStorage.getTvKeyboardEnabled(tvOs: true), isTrue);
    });

    test('does not change the default or stored value off Apple TV', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await TvDisplayStorage.getTvKeyboardEnabled(tvOs: false), isTrue);

      await TvDisplayStorage.setTvKeyboardEnabled(false);
      expect(await TvDisplayStorage.getTvKeyboardEnabled(tvOs: false), isFalse);
    });
  });
}
