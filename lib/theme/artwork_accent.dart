import 'dart:collection';

import 'package:flutter/material.dart';

import '../utils/dominant_color.dart';
import 'app_theme.dart';

/// The artwork's own colour, offered to the widgets that want it.
///
/// ## Why this is a scoped VALUE and not a derived theme
///
/// The obvious design — `AppTheme.withArtworkAccent(colour)` — does not work.
/// `AppTheme.fromDetail` derives a dozen subprofiles from `core.accent`, while
/// `DetailTheme` deliberately exposes only `withText` and no general
/// `copyWith` (fifty optional parameters invite drive-by theme edits that
/// bypass the registry). So swapping the accent would move every derived
/// subprofile while leaving `focus`, `state`, `callout`, `btnFill` and the
/// washes on the old colour. A half-recoloured theme is worse than an
/// unrecoloured one.
///
/// This is the shape `merged_series_detail_screen` already uses and proves —
/// `_theme.useArtworkAccent ? _accent : _theme.accent` — promoted to a shared
/// mechanism instead of copied a third time.
///
/// ## The rules a consumer must follow
///
/// * **Identity only.** Take the artwork accent where the site paints *this
///   title's* colour. Never for a MEANING colour — `state`, `callout`,
///   `error`, `success`, `liveDot` — because an arbitrary poster would
///   redefine what green means.
/// * **`useArtworkAccent` gates it.** A fixed-palette theme (Noir's white,
///   Phosphor's amber) is never contaminated; [resolve] enforces this so a
///   consumer cannot forget.
/// * **Ink is still scored.** An arbitrary poster colour is an arbitrary fill,
///   so anything drawn ON it goes through `AppTheme.inkOn` and any cursor over
///   it through `DetailTheme.focusOn`, exactly as for a designed token.
class ArtworkAccentScope extends InheritedTheme {
  /// The extracted, ground-normalised colour, or null for "no artwork".
  final Color? accent;

  const ArtworkAccentScope({
    super.key,
    required this.accent,
    required super.child,
  });

  /// An [InheritedTheme], not a plain `InheritedWidget`: `InheritedTheme
  /// .capture` silently SKIPS plain inherited widgets, so a dialog or sheet
  /// launched from a themed page would lose the accent. The same reason
  /// `AppThemeScope` and `DetailThemeScope` are both InheritedThemes.
  @override
  Widget wrap(BuildContext context, Widget child) =>
      ArtworkAccentScope(accent: accent, child: child);

  @override
  bool updateShouldNotify(ArtworkAccentScope oldWidget) =>
      oldWidget.accent != accent;

  /// The raw scoped colour. Most callers want [resolve].
  static Color? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ArtworkAccentScope>()
      ?.accent;

  /// The colour a site should actually paint: the artwork's where the theme
  /// invites it, the theme's own otherwise.
  ///
  /// [fallback] defaults to the theme's accent; pass a subprofile accent where
  /// that is the identity the site normally uses.
  static Color resolve(BuildContext context, AppTheme app, {Color? fallback}) {
    final base = fallback ?? app.core.accent;
    if (!app.core.useArtworkAccent) return base;
    return of(context) ?? base;
  }
}

/// [raw] pulled into a range that reads on [theme]'s own ground.
///
/// [extractDominantColor] normalises "into an accent range that reads well on
/// a **dark** UI" — saturation floored at 0.45, value clamped to 0.55–0.85.
/// That is right for nineteen themes and wrong for the two paper ones, where a
/// mid-value accent lands at 2:1 against the page. Rather than teach the
/// extractor about themes, the colour is re-targeted here, against the ground
/// it will actually be seen on.
///
/// Hue and saturation are preserved — those are the artwork's contribution.
/// Only lightness moves, and it moves by bisecting toward a target LUMINANCE
/// rather than an HSL lightness, because lightness is not perceptual: at the
/// same L a saturated blue and a yellow differ by a factor of six in what the
/// eye reads. (The same lesson `_accentRamp` in `app_theme.dart` learned.)
Color normaliseAccentFor(Color raw, AppTheme theme) {
  final ground = theme.core.ground.withValues(alpha: 1);
  final groundLum = ground.computeLuminance();
  // Two different numbers on purpose, and they are not in conflict:
  //
  //  * 3.0 is the ACCEPTANCE bar. An accent that already reads at 3:1 is left
  //    completely alone, because hue and saturation are the artwork's
  //    contribution and moving them when there is no problem just makes every
  //    poster the same colour.
  //  * 4.5 is the REPAIR target. When a colour does have to move, it is worth
  //    moving it clear of the bar rather than to it — a colour parked exactly
  //    at 3:1 is one theme tweak away from failing again.
  const acceptable = 3.0;
  const repairTo = 4.5;
  final target = groundLum > 0.5
      ? (groundLum + 0.05) / repairTo - 0.05 // paper: go deep
      : (groundLum + 0.05) * repairTo - 0.05; // ink: come up
  final hsl = HSLColor.fromColor(raw);
  if (_ratio(raw.computeLuminance(), groundLum) >= acceptable) return raw;
  return _atLuminance(hsl, target.clamp(0.0, 1.0));
}

double _ratio(double a, double b) {
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

/// Bisection on HSL lightness, which luminance increases monotonically with
/// for a fixed hue and saturation — and whose ends are black and white, so
/// every target in (0,1) is reachable whatever the hue.
Color _atLuminance(HSLColor hsl, double target) {
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 18; i++) {
    final mid = (lo + hi) / 2;
    if (hsl.withLightness(mid).toColor().computeLuminance() < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return hsl.withLightness((lo + hi) / 2).toColor();
}

/// Extracted accents, kept so revisiting a title is free.
///
/// Extraction is a 32px decode plus a ~1,000-pixel pass — cheap, but not free
/// on a 2 GB box, and both existing call sites re-run it every time their
/// screen opens. A small LRU turns "every open" into "once per title per
/// process", which is what makes it reasonable to call from more places.
///
/// Bounded and ordered: [LinkedHashMap] preserves insertion order, so the
/// oldest key is the first one, and a re-read moves its key to the end.
class DominantColorCache {
  DominantColorCache._();

  static const int _capacity = 64;
  static final LinkedHashMap<String, Color?> _entries =
      LinkedHashMap<String, Color?>();
  static final Map<String, Future<Color?>> _inFlight = {};

  /// The dominant colour of [url], extracting it at most once.
  ///
  /// A null RESULT is cached too: an image that yields nothing colourful (a
  /// black-and-white poster) would otherwise be re-decoded on every visit.
  static Future<Color?> of(String url, ImageProvider provider) {
    if (_entries.containsKey(url)) {
      final hit = _entries.remove(url);
      _entries[url] = hit; // touch: move to the young end
      return Future.value(hit);
    }
    // Two cards for the same title mounting in the same frame must not decode
    // twice; they share the one flight.
    final pending = _inFlight[url];
    if (pending != null) return pending;

    final future = extractDominantColor(provider).then((c) {
      _put(url, c);
      return c;
    }).catchError((_) {
      _put(url, null);
      return null;
    })
        // Block body, NOT an arrow: the map stores this wrapped future, so an
        // arrow callback would hand whenComplete the removed value — a future
        // — which it then awaits: the future deadlocks on itself and the
        // first awaiter never gets its accent (the cache masks it for
        // everyone else).
        .whenComplete(() {
      _inFlight.remove(url);
    });
    _inFlight[url] = future;
    return future;
  }

  static void _put(String url, Color? c) {
    if (_entries.length >= _capacity && !_entries.containsKey(url)) {
      _entries.remove(_entries.keys.first);
    }
    _entries[url] = c;
  }

  @visibleForTesting
  static int get debugSize => _entries.length;

  /// TEST-ONLY: seed an entry through the same eviction path [of] uses.
  ///
  /// Exists because the decode path is untestable in a widget test: image
  /// resolution is real engine work, and under the test binding's clock the
  /// stream never completes, so a test that goes through [of] hangs rather
  /// than fails. The POLICY — bounded size, oldest-out, a re-read counting as
  /// young — is what has bugs in it, and this exercises exactly that.
  @visibleForTesting
  static void debugPut(String url, Color? c) => _put(url, c);

  /// TEST-ONLY: current keys, oldest first.
  @visibleForTesting
  static List<String> get debugKeys => _entries.keys.toList();

  /// TEST-ONLY: read through the touch path without decoding.
  @visibleForTesting
  static void debugTouch(String url) {
    if (!_entries.containsKey(url)) return;
    final hit = _entries.remove(url);
    _entries[url] = hit;
  }

  @visibleForTesting
  static void debugClear() {
    _entries.clear();
    _inFlight.clear();
  }
}
