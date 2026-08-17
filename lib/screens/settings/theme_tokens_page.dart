import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/analytics_service.dart';
import '../../theme/app_ambience.dart';
import '../../theme/app_art.dart';
import '../../theme/app_focus.dart';
import '../../theme/app_light.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_sound.dart';
import '../../theme/app_surface.dart';
import '../../theme/app_theme_controller.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/theme_overrides.dart';
import '../../theme/theme_palette.dart';
import '../../widgets/detail/theme/detail_theme.dart' show DetailFontRole;
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

/// One editable token: what it is called, and what it may be set to.
///
/// The page is DATA, not twenty hand-written rows. Twenty rows is twenty
/// chances to get DPAD focus, reset behaviour or the "follow the Look" state
/// subtly different from its neighbour.
class _Knob {
  final String key;
  final String label;
  final String blurb;

  /// Null for a colour knob — those open the swatch grid instead.
  final List<SettingsSelectOption>? options;

  /// Which swatch set this knob picks from. Marks and surfaces are different
  /// palettes: the mark palette contains nothing dark enough to be a
  /// background, and the ink list is deliberately five entries because ink is
  /// a legibility decision rather than a taste one.
  final List<Swatch>? palette;

  const _Knob(this.key, this.label, this.blurb, [this.options, this.palette]);

  bool get isColour => options == null;
}

class _Section {
  final String title;
  final List<_Knob> knobs;
  const _Section(this.title, this.knobs);
}

List<SettingsSelectOption> _enumOptions<T>(
  List<T> values,
  String Function(T) name, [
  Map<String, String> blurbs = const {},
]) => [
  for (final v in values)
    SettingsSelectOption(name(v), _title(name(v)), blurbs[name(v)]),
];

/// `dimChrome` → `Dim chrome`. The enum names are the storage format, so this
/// is the one place they are made presentable.
String _title(String camel) {
  final buf = StringBuffer();
  for (var i = 0; i < camel.length; i++) {
    final c = camel[i];
    if (i > 0 && c.toUpperCase() == c && c.toLowerCase() != c) {
      buf.write(' ${c.toLowerCase()}');
    } else if (i == 0) {
      buf.write(c.toUpperCase());
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}

List<SettingsSelectOption> _scaleOptions(List<double> values) => [
  for (final v in values)
    SettingsSelectOption(
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString(),
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString(),
    ),
];

final List<_Section> _sections = [
  _Section('Colour', const [
    _Knob('accent', 'Accent', 'The colour the app uses to mean "this one".'),
    _Knob('focusColor', 'Focus', 'The cursor. Pick something you can find.'),
    _Knob('state', 'Progress', 'Progress bars and watched marks.'),
    _Knob('callout', 'Callout', 'Badges and highlights.'),
  ]),
  _Section('Ground', [
    _Knob('ground', 'Background', 'The page behind everything.', null,
        ThemePalette.grounds),
    // Pane, fill and rail are NOT separately editable. Polarity is one
    // decision — see `DetailTheme.withTokens`. Offering four independent
    // surfaces produced combinations no single ink could read on.
    _Knob('ink', 'Text',
        'Everything written on top. Kept readable against the background.',
        null, ThemePalette.inks),
  ]),
  _Section('Shape', [
    _Knob('radius', 'Corners', 'How round a card is. 0 squares everything.',
        _scaleOptions([0, 2, 4, 6, 8, 12, 16, 20, 28])),
    _Knob('pillRadius', 'Buttons', 'Pill-shaped at the top, squared at 0.',
        _scaleOptions([0, 4, 8, 12, 20, 999])),
  ]),
  _Section('Type', [
    _Knob('displayFont', 'Titles', 'The face titles are set in.',
        _enumOptions(DetailFontRole.values, (e) => e.name)),
    _Knob('bodyFont', 'Body', 'Everything else.',
        _enumOptions(DetailFontRole.values, (e) => e.name)),
  ]),
  _Section('Focus', [
    _Knob('focusExpression', 'Cursor', 'How the focused thing shows it.',
        _enumOptions(FocusExpression.values, (e) => e.name, const {
          'ring': 'A drawn outline.',
          'scale': 'It grows.',
          'lift': 'It rises, with a shadow.',
          'invert': 'It swaps ink and ground.',
          'flood': 'It fills with the focus colour.',
          'parallax': 'It lifts and tilts, tvOS style.',
        })),
  ]),
  _Section('Motion', [
    _Knob('motion', 'Character', 'The tempo everything moves at.',
        _enumOptions(MotionCharacter.values, (e) => e.name, const {
          'standard': 'The shipped feel.',
          'snap': 'Instant. Instruments do not glide.',
          'glide': 'Long, soft decelerations.',
        })),
    _Knob('entrance', 'Entrances', 'How new content arrives.',
        _enumOptions(EntranceStyle.values, (e) => e.name)),
    _Knob('idle', 'When idle', 'What happens when you stop touching it.',
        _enumOptions(IdlePolicy.values, (e) => e.name)),
  ]),
  _Section('Surfaces', [
    _Knob('separation', 'Separation', 'How one surface is told from another.',
        _enumOptions(SeparationModel.values, (e) => e.name, const {
          'space': 'Nothing drawn. Space does the work.',
          'rule': 'Hairlines.',
          'glass': 'Translucent, blurred panels.',
          'fill': 'Solid tinted boxes.',
        })),
    _Knob('scrim', 'Scrims', 'The fade behind text on artwork.',
        _enumOptions(ScrimStyle.values, (e) => e.name)),
  ]),
  _Section('Artwork', [
    _Knob('frame', 'Frames', 'How posters are edged.',
        _enumOptions(ArtFrame.values, (e) => e.name)),
    _Knob('grade', 'Grade', 'A colour treatment over artwork.',
        _enumOptions(ArtGrade.values, (e) => e.name)),
    _Knob('reactiveRoom', 'Room colour',
        'How far the page takes its colour from what you are looking at.',
        _scaleOptions([0, 0.1, 0.2, 0.35, 0.5, 0.75, 1])),
    _Knob('artworkAccent', 'Accent from artwork',
        'Let a poster\'s own colour replace the accent.', const [
      SettingsSelectOption('false', 'Off'),
      SettingsSelectOption('true', 'On'),
    ]),
  ]),
  _Section('Texture', [
    _Knob('grain', 'Film grain', 'Off on TV regardless.',
        _scaleOptions([0, 0.1, 0.2, 0.35, 0.5])),
    _Knob('sheen', 'Sheen', 'A highlight along the top of a surface.',
        _scaleOptions([0, 0.1, 0.2, 0.35, 0.5])),
    _Knob('vignette', 'Vignette', 'Darkening toward the edges.',
        _scaleOptions([0, 0.1, 0.2, 0.35, 0.5])),
    _Knob('bloom', 'Focus glow', 'A halo around the cursor, in pixels.',
        _scaleOptions([0, 8, 14, 18, 22, 26, 34])),
  ]),
  _Section('Feedback', [
    _Knob('feedback', 'Sound and haptics', 'What a press feels like.',
        _enumOptions(FeedbackCharacter.values, (e) => e.name)),
    _Knob('skeleton', 'While loading', 'What a not-yet-arrived thing looks like.',
        _enumOptions(SkeletonStyle.values, (e) => e.name)),
  ]),
];

/// Appearance → Looks → **Advanced**.
///
/// Every token a Look sets, editable one at a time. Changes apply LIVE and the
/// page does not preview them — the app is the preview, which is both cheaper
/// and the only honest representation of what a token does across twenty
/// screens.
class ThemeTokensPage extends StatefulWidget {
  const ThemeTokensPage({super.key});

  @override
  State<ThemeTokensPage> createState() => _ThemeTokensPageState();
}

class _ThemeTokensPageState extends State<ThemeTokensPage> {
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'tokens-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('theme_tokens_settings');
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  ThemeOverrides get _o => AppThemeController.instance.overrides;

  /// `SettingsTile.onTap` is non-nullable, and a disabled row still has to
  /// supply something. Doing nothing is the honest behaviour for "there is
  /// nothing to reset".
  static Future<void> _noop() async {}

  Future<void> _set(String key, String? value) async {
    await AppThemeController.instance.setOverrides(_o.with_(key, value));
    if (mounted) setState(() {});
  }

  Future<void> _resetAll() async {
    await AppThemeController.instance.clearOverrides();
    if (mounted) setState(() {});
  }

  Future<void> _resetSection(_Section s) async {
    var next = _o;
    for (final k in s.knobs) {
      next = next.clear(k.key);
    }
    await AppThemeController.instance.setOverrides(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final o = _o;
    final classic = AppThemeController.instance.isLegacy;

    return SettingsPageScaffold(
      title: 'Advanced',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.tune_rounded,
                  title: 'Advanced',
                  subtitle: 'Every token a Look sets, one at a time',
                ),
                const SizedBox(height: 18),

                if (classic)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SettingsInfoBanner(
                      icon: Icons.info_outline_rounded,
                      text: 'Classic is the unthemed look — it has no tokens '
                          'to edit. Pick any other Look first and these will '
                          'take effect.',
                    ),
                  ),

                // Reset sits FIRST, deliberately.
                //
                // The one edit that can make the app unreadable is a ground or
                // ink you cannot see against — and the way out must not require
                // reading the screen or scrolling to the bottom of it.
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: _RescueRow(
                    enabled: o.isNotEmpty,
                    label: o.isEmpty
                        ? 'Nothing changed yet — following the Look'
                        : '${o.count} '
                            '${o.count == 1 ? "change" : "changes"} '
                            'over the Look',
                    onTap: _resetAll,
                  ),
                ),
                const SizedBox(height: 14),

                for (final section in _sections) ...[
                  SettingsSectionLabel(section.title),
                  SettingsSection(
                    title: '',
                    children: [
                      for (final knob in section.knobs)
                        _row(context, app, knob, o),
                      if (section.knobs.any((k) => o.valueOf(k.key) != null))
                        SettingsTile(
                          icon: Icons.undo_rounded,
                          title: 'Reset ${section.title.toLowerCase()}',
                          subtitle: 'Give this section back to the Look',
                          onTap: () => _resetSection(section),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                Text(
                  'Anything you do not touch follows the Look, including after '
                  'the Look itself is updated. Picking a Look again clears '
                  'these.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: app.settings.dim,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    dynamic app,
    _Knob knob,
    ThemeOverrides o,
  ) {
    final value = o.valueOf(knob.key);
    final following = value == null;
    final subtitle = following
        ? knob.blurb
        : knob.isColour
            ? (ThemePalette.byId(value)?.label ?? knob.blurb)
            : _title(value);

    return SettingsTile(
      icon: knob.isColour ? Icons.palette_outlined : Icons.tune_rounded,
      title: knob.label,
      subtitle: subtitle,
      trailing: following
          ? Text('Look',
              style: TextStyle(fontSize: 12, color: app.settings.dim))
          : knob.isColour
              ? _Dot(color: ThemePalette.colorOf(value))
              : Icon(Icons.check_rounded, size: 18, color: app.settings.accent2),
      onTap: () async =>
          knob.isColour ? await _pickColour(knob) : await _pickOption(knob),
    );
  }

  Future<void> _pickColour(_Knob knob) async {
    final picked = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _SwatchPage(
          title: knob.label,
          selected: _o.valueOf(knob.key),
          palette: knob.palette ?? ThemePalette.all,
        ),
      ),
    );
    if (picked == null) return;
    await _set(knob.key, picked == _kFollow ? null : picked);
  }

  Future<void> _pickOption(_Knob knob) async {
    final picked = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _OptionPage(
          title: knob.label,
          blurb: knob.blurb,
          options: knob.options!,
          selected: _o.valueOf(knob.key),
        ),
      ),
    );
    if (picked == null) return;
    await _set(knob.key, picked == _kFollow ? null : picked);
  }
}

/// The way out, painted in colours the user cannot change.
///
/// Every other row on this page is themed, which is correct — except for this
/// one. Ground and ink are freely editable, and the honest consequence is that
/// someone can choose a pair they cannot read. If the reset were themed too, it
/// would be invisible in exactly the situation it exists for.
///
/// So: fixed near-black on fixed white, a contrast no override can touch. The
/// guard on this feature is recovery, not prevention, and this is the recovery.
class _RescueRow extends StatefulWidget {
  final bool enabled;
  final String label;
  final Future<void> Function() onTap;

  const _RescueRow({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  @override
  State<_RescueRow> createState() => _RescueRowState();
}

class _RescueRowState extends State<_RescueRow> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF101012);
    const surface = Color(0xFFF2F2F4);
    return Focus(
      canRequestFocus: widget.enabled,
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (_, e) {
        if (!widget.enabled || e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k != LogicalKeyboardKey.enter &&
            k != LogicalKeyboardKey.select &&
            k != LogicalKeyboardKey.space &&
            k != LogicalKeyboardKey.gameButtonA) {
          return KeyEventResult.ignored;
        }
        widget.onTap();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: widget.enabled ? surface : surface.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? ink : Colors.transparent,
              width: 3,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.restart_alt_rounded, size: 22, color: ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reset everything',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sentinel a picker returns for "go back to whatever the Look says".
///
/// A separate value rather than "no selection", because dismissing a picker and
/// choosing to follow the Look are different intents and must not be confused.
const String _kFollow = '__follow__';

class _Dot extends StatelessWidget {
  final Color? color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
      );
}

/// The 50-swatch grid. A grid rather than a list because fifty rows is a very
/// long scroll on a remote, and colour is recognised rather than read.
class _SwatchPage extends StatefulWidget {
  final String title;
  final String? selected;
  final List<Swatch> palette;

  const _SwatchPage({
    required this.title,
    required this.selected,
    required this.palette,
  });

  @override
  State<_SwatchPage> createState() => _SwatchPageState();
}

class _SwatchPageState extends State<_SwatchPage> {
  // Without this the route opens with focus on its FocusScopeNode: OK does
  // nothing, and the first arrow press lands somewhere decided by geometry
  // rather than by intent.
  final FocusNode _entry = FocusNode(
    debugLabel: 'swatch-entry',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _entry.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final title = widget.title;
    final selected = widget.selected;
    return SettingsPageScaffold(
      title: title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  focusNode: _entry,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      SettingsTile(
                        icon: Icons.auto_awesome_rounded,
                        title: 'Follow the Look',
                        subtitle: selected == null
                            ? 'Currently following'
                            : 'Give this colour back to the Look',
                        onTap: () async =>
                            Navigator.of(context).pop(_kFollow),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final s in widget.palette)
                      _SwatchTile(
                        swatch: s,
                        selected: s.id == selected,
                        accent: app.settings.accent2,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchTile extends StatefulWidget {
  final Swatch swatch;
  final bool selected;
  final Color accent;

  const _SwatchTile({
    required this.swatch,
    required this.selected,
    required this.accent,
  });

  @override
  State<_SwatchTile> createState() => _SwatchTileState();
}

class _SwatchTileState extends State<_SwatchTile> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      // `GestureDetector.onTap` never fires for a remote, so a swatch built
      // only from a gesture would be visible, focusable and completely inert
      // on a television.
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        final ok = k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.space ||
            k == LogicalKeyboardKey.gameButtonA;
        if (!ok) return KeyEventResult.ignored;
        Navigator.of(context).pop(widget.swatch.id);
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(widget.swatch.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 92,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _focused ? 0.14 : 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? widget.accent
                  : Colors.white.withValues(alpha: 0.10),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 34,
                decoration: BoxDecoration(
                  color: widget.swatch.color,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: widget.selected
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: Colors.black)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                widget.swatch.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The generic enum/scale picker. One page for every non-colour knob.
class _OptionPage extends StatefulWidget {
  final String title;
  final String blurb;
  final List<SettingsSelectOption> options;
  final String? selected;

  const _OptionPage({
    required this.title,
    required this.blurb,
    required this.options,
    required this.selected,
  });

  @override
  State<_OptionPage> createState() => _OptionPageState();
}

class _OptionPageState extends State<_OptionPage> {
  final FocusNode _entry = FocusNode(
    debugLabel: 'option-entry',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _entry.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final title = widget.title;
    final blurb = widget.blurb;
    final options = widget.options;
    final selected = widget.selected;
    return SettingsPageScaffold(
      title: title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  focusNode: _entry,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                  title: '',
                  children: [
                    SettingsTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Follow the Look',
                      subtitle: selected == null
                          ? 'Currently following'
                          : 'Give this back to the Look',
                      onTap: () async =>
                          Navigator.of(context).pop(_kFollow),
                    ),
                    for (final o in options)
                      SettingsTile(
                        icon: o.value == selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        title: o.title,
                        subtitle: o.subtitle ?? '',
                        trailing: o.value == selected
                            ? Icon(Icons.check_rounded,
                                size: 20, color: app.settings.accent2)
                            : const SizedBox.shrink(),
                        onTap: () async =>
                            Navigator.of(context).pop(o.value),
                      ),
                  ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  blurb,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: app.settings.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
