import 'package:flutter/material.dart';

import 'storage_service.dart';

/// App-wide text brightness (Appearance → Text Brightness).
///
/// Exists because pure white on a near-black background glares on OLED
/// panels — the most-requested fix is simply "let me make the text grey".
/// The presets tone down PRIMARY text; surfaces, accents and controls are
/// untouched, and text sitting ON an accent (a button label on indigo, a
/// badge) keeps its designed contrast.
///
/// The colors ride the THEME — `ColorScheme.onSurface` plus a `textTheme`
/// color pass — never a mutable token constant. A token looks cheaper, but a
/// live switch through one can't reach `const` widget subtrees (same
/// instance, the element short-circuits), leaving a half-recolored UI until
/// the user happens to navigate. A new `ThemeData` is an inherited-widget
/// change, which rebuilds dependents even through `const`.
enum TextBrightness {
  bright('bright', 'Bright', 'Pure white — how Debrify has always looked'),
  soft('soft', 'Soft', 'Gently toned down — easier on OLED panels'),
  dim('dim', 'Dim', 'Grey text — for dark rooms and bright screens');

  const TextBrightness(this.value, this.label, this.subtitle);

  /// The stored pref value (`text_brightness`).
  final String value;

  /// Row caption / picker title.
  final String label;

  /// Picker row subtitle.
  final String subtitle;

  static TextBrightness fromPref(String? value) => switch (value) {
        'soft' => soft,
        'dim' => dim,
        _ => bright,
      };

  /// Primary text color, or null for [bright]. Null is deliberate: it means
  /// "override nothing", so the default theme is built from exactly the same
  /// inputs it shipped with before this setting existed — the default cannot
  /// regress by construction.
  Color? get primary => switch (this) {
        bright => null,
        soft => const Color(0xFFE4E4E7), // ~90% white
        dim => const Color(0xFFC4C7CE), // ~78% white, slightly cool
      };

  /// `onSurfaceVariant` override for secondary text. Only [dim] lowers it:
  /// at dim, primary lands nearly on M3's default variant color and titles
  /// would stop reading brighter than subtitles. [soft] keeps enough
  /// distance already, so it changes nothing.
  Color? get secondary => switch (this) {
        bright || soft => null,
        dim => const Color(0xFF9EA0A8),
      };
}

/// Owns the live preset. `DebrifyApp` listens to [notifier] and rebuilds its
/// `ThemeData` when it fires, so a selection applies on the spot — the picker
/// page visibly re-themes under the user as they choose.
abstract final class TextBrightnessController {
  static final ValueNotifier<TextBrightness> notifier =
      ValueNotifier<TextBrightness>(TextBrightness.bright);

  static TextBrightness get current => notifier.value;

  /// Load the stored choice. Called in main() before runApp so the very
  /// first theme build already uses it — reading async after mount would
  /// paint bright text for a frame and then dim it. Swallows storage
  /// failures: a cosmetic pref must never keep the app from starting, and
  /// the notifier already holds the safe default.
  static Future<void> warm() async {
    try {
      notifier.value =
          TextBrightness.fromPref(await StorageService.getTextBrightness());
    } catch (e) {
      debugPrint('TextBrightnessController: warm failed, staying bright: $e');
    }
  }

  /// Apply the choice live, then persist it.
  ///
  /// Publish-first is deliberate: the notifier assignment is synchronous, so
  /// rapid re-selections apply in tap order — persisting first would let two
  /// overlapping writes publish whichever completed last. A failed write
  /// costs only stickiness across restart, never the on-screen state.
  static Future<void> select(TextBrightness choice) async {
    notifier.value = choice;
    try {
      await StorageService.setTextBrightness(choice.value);
    } catch (e) {
      debugPrint('TextBrightnessController: persist failed: $e');
    }
  }
}
