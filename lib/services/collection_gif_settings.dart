import '../utils/platform_util.dart';
import 'home_collections_store.dart';
import 'profiles/profile_preferences.dart';

enum CollectionGifMode {
  visible,
  focused,
  off;

  static CollectionGifMode parse(String? value, {required bool touch}) =>
      values.where((mode) => mode.name == value).firstOrNull ??
      (touch ? visible : focused);
}

abstract final class CollectionGifSettings {
  static bool get isTouch =>
      !PlatformUtil.isTelevision && !PlatformUtil.isDesktop;
  static String keyFor(bool touch) =>
      'home_collections_gif_${touch ? 'touch' : 'remote'}';

  static Future<CollectionGifMode> read() async {
    final touch = isTouch;
    final prefs = await ProfilePreferences.instance();
    return CollectionGifMode.parse(
      prefs.getString(keyFor(touch)),
      touch: touch,
    );
  }

  static Future<void> write(CollectionGifMode mode) async {
    final session = HomeCollectionsStore.captureSession();
    final key = keyFor(isTouch);
    final prefs = await ProfilePreferences.instance();
    HomeCollectionsStore.checkSession(session);
    if (!await prefs.setString(key, mode.name)) {
      throw StateError('Could not save GIF playback setting.');
    }
  }
}
