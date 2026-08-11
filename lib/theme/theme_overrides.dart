import 'dart:convert';

import 'app_ambience.dart';
import 'app_art.dart';
import 'app_focus.dart';
import 'app_light.dart';
import 'app_motion.dart';
import 'app_sound.dart';
import 'app_surface.dart';
import '../widgets/detail/theme/detail_theme.dart' show DetailFontRole;

/// The user's per-token edits, layered over whatever Look is selected.
///
/// **Sparse, and stored as ids rather than values.** A snapshot of the whole
/// theme would freeze what the Look meant on the day it was written, so a Look
/// revision could never reach anyone who had touched a single knob. Holding
/// only the deltas means an untouched token always follows its Look.
///
/// Empty is the overwhelmingly common case and is a fast path everywhere: with
/// no overrides the theme resolves down exactly the code it did before this
/// layer existed.
///
/// Every value is a STRING id — a swatch name, an enum's `name`, or a number
/// formatted back. Nothing here stores a `Color` or an enum instance, so a
/// palette revision, a renamed enum or a rolled-back build all degrade to
/// "follow the Look" instead of throwing on launch.
class ThemeOverrides {
  // ── palette (swatch ids) ──────────────────────────────────────────────────
  final String? accent;
  final String? focusColor;
  final String? state;
  final String? callout;

  // ── ground (swatch ids) ───────────────────────────────────────────────────
  final String? ground;
  final String? pane;
  final String? panel;
  final String? ink;

  // ── shape / type ──────────────────────────────────────────────────────────
  final String? radius;
  final String? pillRadius;
  final String? displayFont;
  final String? bodyFont;

  // ── behaviour (enum names) ────────────────────────────────────────────────
  final String? focusExpression;
  final String? motion;
  final String? entrance;
  final String? idle;
  final String? separation;
  final String? scrim;
  final String? frame;
  final String? grade;
  final String? skeleton;
  final String? feedback;

  // ── scalars ───────────────────────────────────────────────────────────────
  final String? grain;
  final String? sheen;
  final String? vignette;
  final String? bloom;
  final String? reactiveRoom;
  final String? artworkAccent;

  const ThemeOverrides({
    this.accent,
    this.focusColor,
    this.state,
    this.callout,
    this.ground,
    this.pane,
    this.panel,
    this.ink,
    this.radius,
    this.pillRadius,
    this.displayFont,
    this.bodyFont,
    this.focusExpression,
    this.motion,
    this.entrance,
    this.idle,
    this.separation,
    this.scrim,
    this.frame,
    this.grade,
    this.skeleton,
    this.feedback,
    this.grain,
    this.sheen,
    this.vignette,
    this.bloom,
    this.reactiveRoom,
    this.artworkAccent,
  });

  static const ThemeOverrides none = ThemeOverrides();

  /// Every field, keyed the way it is stored. The single source of truth for
  /// serialisation, counting and clearing — adding a knob in one place rather
  /// than five is what keeps those three from drifting apart.
  Map<String, String?> get _fields => {
        'accent': accent,
        'focusColor': focusColor,
        'state': state,
        'callout': callout,
        'ground': ground,
        'pane': pane,
        'panel': panel,
        'ink': ink,
        'radius': radius,
        'pillRadius': pillRadius,
        'displayFont': displayFont,
        'bodyFont': bodyFont,
        'focusExpression': focusExpression,
        'motion': motion,
        'entrance': entrance,
        'idle': idle,
        'separation': separation,
        'scrim': scrim,
        'frame': frame,
        'grade': grade,
        'skeleton': skeleton,
        'feedback': feedback,
        'grain': grain,
        'sheen': sheen,
        'vignette': vignette,
        'bloom': bloom,
        'reactiveRoom': reactiveRoom,
        'artworkAccent': artworkAccent,
      };

  String? valueOf(String key) => _fields[key];

  bool get isEmpty => _fields.values.every((v) => v == null);
  bool get isNotEmpty => !isEmpty;

  /// How many tokens the user has taken over. Shown as "Look — 3 changes".
  int get count => _fields.values.where((v) => v != null).length;

  /// Whether anything here reaches the DetailTheme core.
  ///
  /// The core is resolved and memoized separately from the token groups, so
  /// this decides whether that work is needed at all.
  ///
  /// `reactiveRoom` and `artworkAccent` are here because the core carries them
  /// as `washOpacity` and `useArtworkAccent`, and the detail layouts read those
  /// fields directly rather than the token groups — so a spec-arm-only edit
  /// would take effect everywhere except the page it is most visible on.
  bool get touchesCore => const [
        'accent',
        'focusColor',
        'state',
        'callout',
        'ground',
        'pane',
        'panel',
        'ink',
        'radius',
        'pillRadius',
        'displayFont',
        'bodyFont',
        'grain',
        'reactiveRoom',
        'artworkAccent',
        // Separation is a SurfaceTokens value, but the core carries its
        // consequences — panel, hair, ghostFill, ghostBorder are all derived
        // from it, and the detail layouts paint those directly. Left out, a
        // `space` look would lose its fills everywhere except the detail page.
        'separation',
      ].any((k) => _fields[k] != null);

  /// This set with [key] set to [value], or cleared when [value] is null.
  ThemeOverrides with_(String key, String? value) =>
      fromMap({..._fields, key: value});

  ThemeOverrides clear(String key) => with_(key, null);

  static ThemeOverrides fromMap(Map<String, String?> m) => ThemeOverrides(
        accent: m['accent'],
        focusColor: m['focusColor'],
        state: m['state'],
        callout: m['callout'],
        ground: m['ground'],
        pane: m['pane'],
        panel: m['panel'],
        ink: m['ink'],
        radius: m['radius'],
        pillRadius: m['pillRadius'],
        displayFont: m['displayFont'],
        bodyFont: m['bodyFont'],
        focusExpression: m['focusExpression'],
        motion: m['motion'],
        entrance: m['entrance'],
        idle: m['idle'],
        separation: m['separation'],
        scrim: m['scrim'],
        frame: m['frame'],
        grade: m['grade'],
        skeleton: m['skeleton'],
        feedback: m['feedback'],
        grain: m['grain'],
        sheen: m['sheen'],
        vignette: m['vignette'],
        bloom: m['bloom'],
        reactiveRoom: m['reactiveRoom'],
        artworkAccent: m['artworkAccent'],
      );

  // ── resolution ────────────────────────────────────────────────────────────
  //
  // Each of these returns null when the stored value is absent OR
  // unrecognised. Null means "follow the Look", which is the only safe answer
  // for a value written by a build that knew an enum this one does not.

  static T? _enum<T>(String? name, List<T> values, String Function(T) nameOf) {
    if (name == null) return null;
    for (final v in values) {
      if (nameOf(v) == name) return v;
    }
    return null;
  }

  double? _double(String? raw, {double? min, double? max}) {
    if (raw == null) return null;
    final v = double.tryParse(raw);
    // `double.tryParse` happily returns NaN and Infinity, and neither clamp
    // comparison below is true for NaN — so a stored "NaN" would sail through
    // into a radius or an alpha and fail at paint time rather than falling back
    // to the Look, which is what every other bad value here does.
    if (v == null || !v.isFinite) return null;
    if (min != null && v < min) return min;
    if (max != null && v > max) return max;
    return v;
  }

  FocusExpression? get resolvedFocusExpression =>
      _enum(focusExpression, FocusExpression.values, (e) => e.name);

  MotionCharacter? get resolvedMotion =>
      _enum(motion, MotionCharacter.values, (e) => e.name);

  EntranceStyle? get resolvedEntrance =>
      _enum(entrance, EntranceStyle.values, (e) => e.name);

  IdlePolicy? get resolvedIdle => _enum(idle, IdlePolicy.values, (e) => e.name);

  SeparationModel? get resolvedSeparation =>
      _enum(separation, SeparationModel.values, (e) => e.name);

  ScrimStyle? get resolvedScrim => _enum(scrim, ScrimStyle.values, (e) => e.name);

  ArtFrame? get resolvedFrame => _enum(frame, ArtFrame.values, (e) => e.name);

  ArtGrade? get resolvedGrade => _enum(grade, ArtGrade.values, (e) => e.name);

  SkeletonStyle? get resolvedSkeleton =>
      _enum(skeleton, SkeletonStyle.values, (e) => e.name);

  FeedbackCharacter? get resolvedFeedback =>
      _enum(feedback, FeedbackCharacter.values, (e) => e.name);

  DetailFontRole? get resolvedDisplayFont =>
      _enum(displayFont, DetailFontRole.values, (e) => e.name);

  DetailFontRole? get resolvedBodyFont =>
      _enum(bodyFont, DetailFontRole.values, (e) => e.name);

  double? get resolvedRadius => _double(radius, min: 0, max: 40);
  double? get resolvedPillRadius => _double(pillRadius, min: 0, max: 999);
  double? get resolvedGrain => _double(grain, min: 0, max: 1);
  double? get resolvedSheen => _double(sheen, min: 0, max: 1);
  double? get resolvedVignette => _double(vignette, min: 0, max: 1);
  /// A logical-pixel radius, not a fraction — the shipped specs use 18 to 26.
  /// Clamped to 0..1 it was a control that could not be seen to do anything.
  double? get resolvedBloom => _double(bloom, min: 0, max: 48);
  double? get resolvedReactiveRoom => _double(reactiveRoom, min: 0, max: 1);

  bool? get resolvedArtworkAccent => switch (artworkAccent) {
        'true' => true,
        'false' => false,
        _ => null,
      };

  // ── storage ───────────────────────────────────────────────────────────────

  Map<String, String> toJsonMap() => {
        for (final e in _fields.entries)
          if (e.value != null) e.key: e.value!,
      };

  String encode() => jsonEncode(toJsonMap());

  /// Never throws. A malformed or half-written preference degrades to "no
  /// overrides", which is a working app; anything else is a launch crash for a
  /// cosmetic setting.
  static ThemeOverrides decode(String? raw) {
    if (raw == null || raw.isEmpty) return none;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return none;
      return fromMap({
        for (final e in decoded.entries)
          if (e.key is String && e.value is String && (e.value as String).isNotEmpty)
            e.key as String: e.value as String,
      });
    } catch (_) {
      return none;
    }
  }
}
