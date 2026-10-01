import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('debrify_tv_style coercion (total, both directions)', () {
    test('an unknown stored value reads as grid', () async {
      // Written by a newer build, read by this one: land on the layout that
      // always existed rather than rendering nothing.
      SharedPreferences.setMockInitialValues({
        'debrify_tv_style': 'holodeck',
      });
      expect(await DebrifyTvStorage.getDebrifyTvStyle(), 'grid');
      expect(DebrifyTvStorage.debrifyTvStyleCached, 'grid');
    });

    test('an unknown value passed to the setter persists as grid', () async {
      SharedPreferences.setMockInitialValues({});
      await DebrifyTvStorage.setDebrifyTvStyle('holodeck');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debrify_tv_style'), 'grid');
      expect(DebrifyTvStorage.debrifyTvStyleCached, 'grid');
    });

    test('spotlight round-trips, and the mirror is published before the read',
        () async {
      SharedPreferences.setMockInitialValues({});
      final write = DebrifyTvStorage.setDebrifyTvStyle('spotlight');
      // Mirror BEFORE the await — anything reading synchronously on the next
      // frame already sees the choice.
      expect(DebrifyTvStorage.debrifyTvStyleCached, 'spotlight');
      await write;
      expect(await DebrifyTvStorage.getDebrifyTvStyle(), 'spotlight');
    });

    test('an absent key reads as grid', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DebrifyTvStorage.getDebrifyTvStyle(), 'grid');
    });
  });
}
