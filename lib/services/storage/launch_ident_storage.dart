import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

final class LaunchIdentStorage {
  const LaunchIdentStorage._();

  static const String _launchAnimationKey = 'launch_animation';
  // MUST stay in step with kLaunchIdents — an id missing here is silently
  // normalized back to the default, so the picker would appear not to save.
  static const Set<String> _launchAnimationValues = {
    'drop',
    'marquee',
    'prism',
    'horizon',
    'collider',
    'neon',
    'chrome',
    'monogram',
    'aperture',
    'blueprint',
    'ripple',
    'ember',
    'swiss',
    'origami',
    'anamorphic',
    'constellation',
    'silk',
    'rackfocus',
    'imprint',
    'frost',
    'trace',
  };

  /// Exposed so a test can assert this set and `kLaunchIdents` agree in BOTH
  /// directions — drift either way silently strands the pref on the default.
  @visibleForTesting
  static Set<String> get launchAnimationValues => _launchAnimationValues;

  /// Which launch ident the splash plays (Appearance → Launch Animation).
  /// Values are the ids in `widgets/launch/launch_ident.dart`; 'trace' (Trace)
  /// is the default, 'collider' and before it 'horizon' are the idents it
  /// replaced as such, and 'drop' is the original splash.
  ///
  /// [launchAnimationCached] mirrors it for SYNCHRONOUS reads: AppInitializer
  /// builds its splash in initState, before any async pref read could land.
  /// Warmed in main() before runApp and kept in sync by the setter.
  ///
  /// Normalizes toward the default on BOTH sides — an unrecognized value has
  /// to mean the default for the reader and the writer alike. Only installs
  /// that never CHOSE move when this changes: an explicit 'collider' is a
  /// stored value and keeps playing Collider.
  static String launchAnimationCached = 'trace';
  static const importedLaunchAnimationKey = 'imported_launch_animation_v1';
  static String? importedLaunchAnimationCached;
  static final Lock _launchSelectionLock = Lock();
  static int _launchSelectionGeneration = 0;

  static Future<String> getLaunchAnimation() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_launchAnimationKey);
    final imported = prefs.getString(importedLaunchAnimationKey);
    importedLaunchAnimationCached = _validImportedLaunchId(imported) ? imported : null;
    launchAnimationCached = _launchAnimationValues.contains(value) ? value! : 'trace';
    return launchAnimationCached;
  }

  static bool _validImportedLaunchId(String? value) => value != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

  static Future<void> setLaunchAnimation(String value) => _setLaunchSelection(
    builtIn: _launchAnimationValues.contains(value) ? value : 'trace',
  );

  static Future<void> setImportedLaunchAnimation(String id) {
    if (!_validImportedLaunchId(id)) throw ArgumentError.value(id, 'id');
    return _setLaunchSelection(imported: id);
  }

  static Future<void> clearImportedLaunchAnimationIf(String id) => _setLaunchSelection(clearIf: id);

  static Future<void> _setLaunchSelection({
    String? builtIn,
    String? imported,
    String? clearIf,
  }) {
    final scope = ProfileRuntime.scope.value;
    final generation = clearIf == null ? ++_launchSelectionGeneration : _launchSelectionGeneration;
    return _launchSelectionLock.synchronized(() async {
      if (scope != ProfileRuntime.scope.value || generation != _launchSelectionGeneration) {
        return;
      }
      final prefs = await ProfilePreferences.instance();
      if (scope != ProfileRuntime.scope.value || generation != _launchSelectionGeneration) {
        return;
      }
      final previousImport = prefs.getString(importedLaunchAnimationKey);
      if (clearIf != null && previousImport != clearIf) return;
      if (builtIn != null && !await prefs.setString(_launchAnimationKey, builtIn)) {
        throw StateError('Could not save the launch animation');
      }
      // Newer selection writes queue behind this operation and become the
      // final persisted value. Do not publish this one's stale cache meanwhile.
      final saved = imported == null
          ? await prefs.remove(importedLaunchAnimationKey)
          : await prefs.setString(importedLaunchAnimationKey, imported);
      if (!saved) {
        if (scope == ProfileRuntime.scope.value) await getLaunchAnimation();
        throw StateError('Could not save the launch animation selection');
      }
      if (scope == ProfileRuntime.scope.value && generation == _launchSelectionGeneration) {
        importedLaunchAnimationCached = imported;
        if (builtIn != null) launchAnimationCached = builtIn;
      }
    });
  }

  static const String _launchIdentPaletteKey = 'launch_ident_palette';
  static const Set<String> _launchIdentPalettes = {'ident', 'theme'};

  /// Whether the launch ident wears its OWN colours or the app theme's
  /// (Appearance → Launch Animation).
  ///
  /// Defaults to `'ident'`, so nobody's splash changes until they ask. The
  /// ident's art direction — its geometry, its motion, its mark — is the same
  /// either way; only the room's colours move, and only where they stay
  /// legible (see `IdentPalette.fromTheme`).
  ///
  /// Mirrored synchronously for the same reason [launchAnimationCached] is:
  /// AppInitializer builds the splash in `initState`, before any async read
  /// could land.
  static String launchIdentPaletteCached = 'ident';

  static Future<String> getLaunchIdentPalette() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_launchIdentPaletteKey);
    launchIdentPaletteCached = _launchIdentPalettes.contains(value) ? value! : 'ident';
    return launchIdentPaletteCached;
  }

  static Future<void> setLaunchIdentPalette(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _launchIdentPalettes.contains(value) ? value : 'ident';
    // Mirror BEFORE the await: the picker rebuilds on the next frame and the
    // splash reads the mirror synchronously.
    launchIdentPaletteCached = normalized;
    await prefs.setString(_launchIdentPaletteKey, normalized);
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    launchAnimationCached = 'trace';
    importedLaunchAnimationCached = null;
    _launchSelectionGeneration++;
    launchIdentPaletteCached = 'ident';
  }
}
