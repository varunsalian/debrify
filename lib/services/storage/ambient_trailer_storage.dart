import 'package:debrify/models/ambient_trailer_surface.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/foundation.dart';

final class AmbientTrailerStorage {
  const AmbientTrailerStorage._();

  /// Autoplay a trailer behind the detail-page backdrop (OTT-style), when the
  /// metadata addon provides one.
  ///
  /// **Defaults ON everywhere** (generation 2). Two earlier rules are retired
  /// here, and neither should be reintroduced without the reason returning:
  /// "exactly one ambient surface per platform" existed because the process
  /// has a single video output, which [VideoOutputLease] plus a covered
  /// trailer releasing its decoder now enforces directly; and the later
  /// hold-back of OFF-on-TV existed only so an existing box wouldn't start
  /// playing trailers on a page that never did, which the generation
  /// migration now handles deliberately rather than by omission.
  static Future<bool> getDetailTrailerAutoplayEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('detail_trailer_autoplay_enabled') ?? true;
  }

  static Future<void> setDetailTrailerAutoplayEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('detail_trailer_autoplay_enabled', enabled);
  }

  /// Ambient trailer in the hero surfaces — the Home board's spotlight and
  /// the Discover rail.
  ///
  /// **Defaults ON everywhere** (generation 2). This was once hard-off
  /// anywhere but a television, then a form-factor default that kept phones
  /// and tablets opted out on battery-and-cellular grounds. The hero is the
  /// Spotlight layout's centrepiece on every device now, so it starts on and
  /// the toggle in Settings is where a phone user turns it off. The stored
  /// value, once written, wins everywhere.
  static Future<bool> getHomeHeroTrailerEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('home_hero_trailer_enabled') ?? true;
  }

  static Future<void> setHomeHeroTrailerEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('home_hero_trailer_enabled', enabled);
  }

  /// Pref key for the ambient-trailer sound pair, resolved per platform.
  /// Resolves to exactly four keys, spelled out here because the returns
  /// below are interpolated and a grep for a literal name would otherwise
  /// find nothing: `home_hero_trailer_audio_enabled`,
  /// `home_hero_trailer_volume`, `detail_trailer_audio_enabled`,
  /// `detail_trailer_volume`. Any future backup allowlist, reset sweep or
  /// migration has to name all four — enumerating one surface silently drops
  /// the other platform's settings.
  /// Each ambient surface owns its own key even though only one of them can
  /// be live on a device: the TV hero/Discover stage keeps the legacy
  /// `home_hero_` pair (renaming would reset every TV install), the non-TV
  /// detail backdrop gets its own. That separation matters because the old
  /// Settings page offered the hero sound rows on EVERY platform — a phone
  /// user could store "sound off" for a hero that never rendered there, and
  /// with one shared key that dead value would now silently mute their detail
  /// backdrop. Per-surface keys make such writes unreadable instead, so
  /// non-TV starts at the defaults its backdrop has always used.
  ///
  /// Now selected by SURFACE rather than by platform. Picking by platform was
  /// sound while a television could only ever have the Home hero; with the
  /// Showcase detail page also playing trailers, a platform pick would have the
  /// detail backdrop silently reading the Home hero's sound and volume.
  static String _ambientTrailerKeyFor(
    AmbientTrailerSurface surface,
    String suffix,
  ) => switch (surface) {
    AmbientTrailerSurface.homeHero => 'home_hero_trailer_$suffix',
    AmbientTrailerSurface.detail => 'detail_trailer_$suffix',
  };

  /// Whether this platform's ambient trailer plays sound (false = video only).
  /// See [_ambientTrailerKey] for which surface that is. Note the IPTV live
  /// preview is a channel feed, not a trailer, and stays at full volume.
  static Future<bool> getAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
  ) async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_ambientTrailerKeyFor(surface, 'audio_enabled')) ?? true;
  }

  static Future<void> setAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
    bool enabled,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _ambientTrailerKeyFor(surface, 'audio_enabled'),
      enabled,
    );
  }

  /// Ambient trailer volume, percent 10–100. Default 70 — audible but under
  /// the UI, and the level the detail backdrop has always run at. Same
  /// one-surface-per-platform scope as [getAmbientTrailerAudioEnabled].
  static Future<int> getAmbientTrailerVolume(
    AmbientTrailerSurface surface,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_ambientTrailerKeyFor(surface, 'volume')) ?? 70;
    return v.clamp(10, 100);
  }

  static Future<void> setAmbientTrailerVolume(
    AmbientTrailerSurface surface,
    int percent,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _ambientTrailerKeyFor(surface, 'volume'),
      percent.clamp(10, 100),
    );
  }

  /// Android TV: render ambient trailers on a native SurfaceView *under* a
  /// translucent Flutter surface (a hardware overlay plane — Flutter never
  /// composites the video frames) instead of a Flutter Texture. Default on;
  /// the toggle is the escape hatch back to the Texture path for boxes where
  /// the underlay misbehaves. MainActivity reads the same key natively (the
  /// surface mode is fixed at activity creation), so changes take effect on
  /// the next app start.
  static Future<bool> getTvTrailerUnderlayEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('tv_trailer_underlay_enabled') ?? true;
  }

  static Future<void> setTvTrailerUnderlayEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tv_trailer_underlay_enabled', enabled);
  }

  /// First-read-wins snapshot for engine selection. The native side decides
  /// the EFFECTIVE underlay mode at activity creation (user toggle AND device
  /// capability — GLES2-class GPUs can't afford the permanently-translucent
  /// surface, so MainActivity keeps them opaque) and persists it under
  /// `tv_trailer_underlay_effective` BEFORE the first Dart frame. Trust that
  /// over the raw toggle so both sides always agree — an underlay hole
  /// against an opaque Flutter surface would render a black region instead
  /// of video (and the reverse would silently fall back to Texture, which at
  /// least works). Restarting the app applies changes to both sides together.
  static bool? _tvTrailerUnderlaySession;
  static Future<bool> getTvTrailerUnderlayEnabledAtLaunch() async {
    if (_tvTrailerUnderlaySession != null) return _tvTrailerUnderlaySession!;
    final device = await DevicePreferences.instance();
    final effective = device.getBool(
      DevicePreferences.tvTrailerUnderlayEffectiveKey,
    );
    if (effective != null) {
      return _tvTrailerUnderlaySession = effective;
    }
    final prefs = await ProfilePreferences.instance();
    return _tvTrailerUnderlaySession = prefs.getBool('tv_trailer_underlay_enabled') ?? true;
  }

  @visibleForTesting
  static void debugResetTvTrailerUnderlaySession() {
    _tvTrailerUnderlaySession = null;
  }
}
