import 'package:debrify/models/tv_hero_artwork_quality.dart';
import 'package:debrify/models/tv_render_quality.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';

final class TvDisplayStorage {
  const TvDisplayStorage._();

  /// Use the in-app DPAD keyboard for text fields on TV (TvTextField) instead
  /// of the system IME, which can't be navigated with the remote on many
  /// devices (flutter/flutter#177360 — Chromecast/Google TV, some
  /// Philips/Samsung panels). On by default on Android TV. Apple TV defaults
  /// to its system keyboard; the Settings toggle still lets users opt into the
  /// Debrify keyboard.
  ///
  /// [tvKeyboardEnabledCached] mirrors the stored value for synchronous widget
  /// builds — warmed at startup (main.dart) and kept in sync by the setter.
  static bool tvKeyboardEnabledCached = !PlatformUtil.isTvOS;

  // Apple TV keyboard default, generation 1 (2026-08): disable the Debrify
  // keyboard once for every profile, including profiles whose user explicitly
  // enabled it in an older build. The generation is committed only after the
  // new value, so a failed/interrupted write retries safely next launch. Once
  // committed, [setTvKeyboardEnabled] is authoritative and later user changes
  // are never overwritten.
  static const int _currentTvosKeyboardDefaultGeneration = 1;
  static const String _tvosKeyboardDefaultGenerationKey = 'tvos_keyboard_default_generation';

  static Future<bool> getTvKeyboardEnabled({
    @visibleForTesting bool? tvOs,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final runningOnTvOs = tvOs ?? PlatformUtil.isTvOS;
    final generation = prefs.getInt(_tvosKeyboardDefaultGenerationKey) ?? 0;
    if (runningOnTvOs && generation < _currentTvosKeyboardDefaultGeneration) {
      final disabled = await prefs.setBool('tv_keyboard_enabled', false);
      if (disabled) {
        await prefs.setInt(
          _tvosKeyboardDefaultGenerationKey,
          _currentTvosKeyboardDefaultGeneration,
        );
      }
    }
    tvKeyboardEnabledCached = prefs.getBool('tv_keyboard_enabled') ?? !runningOnTvOs;
    return tvKeyboardEnabledCached;
  }

  static Future<void> setTvKeyboardEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tv_keyboard_enabled', enabled);
    tvKeyboardEnabledCached = enabled;
  }

  /// Android TV screen size, as a percentage of the panel's native density.
  ///
  /// A 1080p TV at density 320 gives Flutter a 960x540 logical canvas, so
  /// every screen is drawn 2x and reads as "zoomed in" across a big panel.
  /// A value below 100 makes MainActivity report a proportionally smaller
  /// devicePixelRatio to the engine, which widens the logical canvas (80% ->
  /// 1200x675) so the same layouts fit more and draw smaller — no per-screen
  /// changes involved.
  ///
  /// Read natively from `flutter.tv_ui_scale_percent` BEFORE the Flutter
  /// engine is built, so a change only takes effect on the next cold start.
  /// Android TV only; ignored everywhere else.
  ///
  /// [kTvUiScaleDefault] is 90: at 100 the app reads noticeably larger than
  /// the TV apps people compare it to (Stremio's web-rendered UI lays out
  /// against a canvas far closer to 1920 than to 960), while 80 ran a touch
  /// small for the Canvas-era layouts — Medium is the out-of-the-box balance
  /// and both neighbours are one tap away. MUST stay in step with
  /// MainActivity's `computeUiScale` fallback.
  static const List<int> kTvUiScaleOptions = [100, 90, 80];
  static const int kTvUiScaleDefault = 90;

  static Future<int> getTvUiScalePercent() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getInt('tv_ui_scale_percent');
    return kTvUiScaleOptions.contains(stored) ? stored! : kTvUiScaleDefault;
  }

  static Future<void> setTvUiScalePercent(int percent) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt('tv_ui_scale_percent', percent);
  }

  /// Android TV rendering mode — whether the Flutter UI is rastered at the
  /// panel's own resolution or at a ~720p buffer the TV's scaler blows back
  /// up for free.
  ///
  /// GLES2-class boxes are fill-rate bound: the same build at 720p feels near
  /// native on hardware that judders at 1080p. MainActivity decides this in
  /// `computeRenderScale` and has always been able to be overridden by
  /// `flutter.tv_low_res_render` — there was simply no way to set it. This is
  /// that way.
  ///
  /// TRI-STATE, and the absence of the key is load-bearing: native reads it as
  /// `getBoolean(key, auto)` where `auto` IS the device decision, so
  /// [TvRenderQuality.auto] must REMOVE the key rather than write `false`.
  /// Writing `false` on a weak TV would strip the 720p subsidy off the very
  /// devices that need it — a silent, permanent regression on the hardware
  /// least able to absorb it.
  ///
  /// Read natively before the engine is built, so a change lands on the next
  /// cold start. Android TV only; ignored everywhere else.
  static const String _tvRenderQualityKey = 'tv_low_res_render';

  static Future<TvRenderQuality> getTvRenderQuality() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getBool(_tvRenderQualityKey);
    if (stored == null) return TvRenderQuality.auto;
    return stored ? TvRenderQuality.fast : TvRenderQuality.sharp;
  }

  static Future<void> setTvRenderQuality(TvRenderQuality quality) async {
    final prefs = await ProfilePreferences.instance();
    switch (quality) {
      case TvRenderQuality.auto:
        await prefs.remove(_tvRenderQualityKey);
      case TvRenderQuality.sharp:
        await prefs.setBool(_tvRenderQualityKey, false);
      case TvRenderQuality.fast:
        await prefs.setBool(_tvRenderQualityKey, true);
    }
  }

  /// What MainActivity ACTUALLY decided for the engine currently running —
  /// written natively on every launch (`renderScale < 0.999f`), so under
  /// [TvRenderQuality.auto] it's the only way to see which branch this TV
  /// landed on. Also the honest answer after a change that hasn't been cold-
  /// started into yet: the pref says what will happen, this says what is.
  ///
  /// Written on every ANDROID launch, phones included (the `putBoolean` sits
  /// outside any TV guard) — off TV `renderScale` stays 1.0, so a phone reads
  /// `false`, not null. Null means MainActivity never ran at all: iOS, macOS,
  /// desktop. Callers must treat null as "unknown", never as "full res".
  static Future<bool?> getTvLowResRenderActive() async {
    final device = await DevicePreferences.instance();
    return device.getBool(DevicePreferences.tvLowResRenderActiveKey);
  }

  static const String _tvHeroArtworkQualityKey = 'tv_hero_artwork_quality';

  /// Maximum decode quality for Home hero/stage artwork on Android TV and
  /// tvOS. Unknown values coerce to Automatic so a removed experimental mode
  /// can never strand an installation on an unsupported policy.
  static Future<TvHeroArtworkQuality> getTvHeroArtworkQuality() async {
    final prefs = await ProfilePreferences.instance();
    return TvHeroArtworkQuality.fromStorage(
      prefs.getString(_tvHeroArtworkQualityKey),
    );
  }

  static Future<void> setTvHeroArtworkQuality(
    TvHeroArtworkQuality quality,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_tvHeroArtworkQualityKey, quality.storageValue);
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    tvKeyboardEnabledCached = !PlatformUtil.isTvOS;
  }
}
