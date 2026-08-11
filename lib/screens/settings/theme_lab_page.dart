import 'package:flutter/material.dart';

import '../../services/storage_service.dart';
import '../../theme/app_surface.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/premium_looks.dart';
import '../../theme/theme_spec.dart';
import '../../theme/widgets/app_scrim.dart';
import '../../theme/widgets/focus_expression.dart';
import '../../theme/widgets/glass_surface.dart';
import '../../theme/widgets/themed_skeleton.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

/// Theme Lab — the five looks, live, on real widgets, on the device.
///
/// The single biggest lever on how long a new theme takes to build. Without
/// it, judging a look means building, installing, and walking twenty screens
/// with a remote; with it, it is arrowing through a list. That is the
/// difference between a theme being a half-day job and a two-day one, and it
/// is why this lands in week two rather than at the end.
///
/// It renders the real token consumers — `GlassSurface`, `AppScrim`,
/// `FocusExpressionBox`, `ThemedSkeleton` — rather than mock rectangles, so
/// what you see here is what the app does. The one thing it cannot show is
/// how a look feels in motion across a whole screen; that is what the device
/// builds are for.
///
/// The inspector below each preview answers the question that otherwise costs
/// a rebuild: *what did my accent actually become?*
class ThemeLabPage extends StatefulWidget {
  const ThemeLabPage({super.key});

  @override
  State<ThemeLabPage> createState() => _ThemeLabPageState();
}

class _ThemeLabPageState extends State<ThemeLabPage> {
  /// Null = the live app theme, so the lab can also show what the user is
  /// actually running rather than only the candidates.
  ThemeSpec? _preview;

  /// The built preview, memoized against [_preview].
  ///
  /// `ThemeSpec.build()` runs the whole derivation — twelve subprofiles of
  /// colour maths — and this page calls `setState` on every switch toggle and
  /// every radio tap. Building it in `build()` would redo all of it for a
  /// state change that cannot have altered it.
  AppTheme? _built;

  void _select(ThemeSpec? spec) => setState(() {
    _preview = spec;
    _built = spec?.build();
  });

  @override
  Widget build(BuildContext context) {
    final live = AppThemeScope.of(context);
    final shown = _built ?? live;
    return SettingsPageScaffold(
      title: 'Theme Lab',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const SettingsPageHeader(
            icon: Icons.science_rounded,
            title: 'Theme Lab',
            subtitle: 'The looks, live, on real widgets',
          ),
          const SizedBox(height: 14),
          _picker(live),
          const SizedBox(height: 14),
          _feedback(),
          const SizedBox(height: 18),
          // Everything below renders under the PREVIEWED theme, not the live
          // one — that is the whole point, and it is why the scope is pushed
          // down here rather than wrapping the page.
          AppThemeScope(theme: shown, child: _Preview(theme: shown)),
          const SizedBox(height: 22),
          AppThemeScope(theme: shown, child: _Inspector(theme: shown)),
        ],
      ),
    );
  }

  /// The user's veto over sound and haptics.
  ///
  /// Lives here rather than in the Appearance list because it is a property of
  /// the LOOK, and because this is the page where you find out a look ticks —
  /// the row that lets you turn it off should be the row you are already
  /// looking at.
  Widget _feedback() {
    return SettingsSection(
      title: 'Feedback',
      children: [
        SettingsToggleTile(
          icon: Icons.volume_up_rounded,
          title: 'Interface sounds',
          subtitle: 'Only Console ticks today; every other look is silent',
          value: StorageService.uiSoundsCached,
          onChanged: (v) async {
            await StorageService.setUiSounds(v);
            if (mounted) setState(() {});
          },
        ),
        SettingsToggleTile(
          icon: Icons.vibration_rounded,
          title: 'Haptics',
          subtitle: 'Phones and tablets only — a remote has no actuator',
          value: StorageService.uiHapticsCached,
          onChanged: (v) async {
            await StorageService.setUiHaptics(v);
            if (mounted) setState(() {});
          },
          subtitleMaxLines: 2,
        ),
      ],
    );
  }

  Widget _picker(AppTheme live) {
    return SettingsSection(
      title: 'Preview',
      children: [
        SettingsTile(
          icon: _preview == null
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          title: 'Live theme',
          subtitle: live.label,
          onTap: () async => _select(null),
        ),
        for (final s in PremiumLooks.all)
          SettingsTile(
            icon: _preview?.id == s.id
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            title: s.label,
            subtitle: s.subtitle,
            onTap: () async => _select(s),
          ),
      ],
    );
  }
}

/// Real consumers, one of each, at a size you can judge.
class _Preview extends StatefulWidget {
  final AppTheme theme;
  const _Preview({required this.theme});

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool _focused = true;

  @override
  Widget build(BuildContext context) {
    final app = widget.theme;
    final tv = PlatformUtil.isTelevision;

    return Container(
      decoration: BoxDecoration(
        color: app.core.ground,
        borderRadius: app.shape.br(14),
        border: Border.all(color: app.core.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A hero: artwork, the theme's scrim grammar, and copy over it.
          SizedBox(
            height: 190,
            child: AppScrim(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color.lerp(app.core.accent, app.core.ground, 0.55)!,
                      app.core.railBg,
                    ],
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE WATCHING',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 2,
                        color: app.core.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The Long Night',
                      style: app.type.display(
                        TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: app.core.tx,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(app, 'focus — tap a card'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 132,
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _focused = i == 1),
                            child: FocusExpressionBox(
                              focused: _focused && i == 1,
                              radius: 10,
                              on: app.core.pane,
                              inverted: (c, ink) => _card(app, i, ink: ink),
                              child: _card(app, i),
                            ),
                          ),
                        ),
                        if (i < 2) const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _label(app, 'waiting'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const ThemedSkeleton(width: 74, height: 100),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          ThemedSkeleton(height: 11),
                          SizedBox(height: 7),
                          ThemedSkeleton(width: 120, height: 9),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _label(app, 'sheet — ${app.surface.modelFor(SurfaceFamily.sheet).name}'),
                const SizedBox(height: 8),
                GlassSurface(
                  family: SurfaceFamily.sheet,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow_rounded, color: app.core.tx, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Resume · 48 min left',
                          style: TextStyle(color: app.core.tx, fontSize: 12.5),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: app.core.accent,
                          borderRadius: app.shape.brPill,
                        ),
                        child: Text(
                          '4K',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: app.inkOn(app.core.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tv) ...[
                  const SizedBox(height: 12),
                  Text(
                    'On this device the TV policies apply: no blur, no grain, '
                    'no grading, and static skeletons.',
                    style: TextStyle(fontSize: 11, color: app.core.tx3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(AppTheme app, String s) => Text(
    s.toUpperCase(),
    style: TextStyle(
      fontSize: 9,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w700,
      color: app.core.tx3,
    ),
  );

  Widget _card(AppTheme app, int i, {Color? ink}) {
    final model = app.surface.modelFor(SurfaceFamily.card);
    final filled = model == SeparationModel.fill || model == SeparationModel.glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? app.core.pane : Colors.transparent,
        borderRadius: app.shape.br(10),
        border: model == SeparationModel.space
            ? null
            : Border.all(color: app.core.hair),
      ),
      child: Center(
        child: Text(
          'Card ${i + 1}',
          style: TextStyle(color: ink ?? app.core.tx2, fontSize: 12),
        ),
      ),
    );
  }
}

/// What the twelve decisions actually became.
///
/// The other half of the iteration loop: the preview shows you that something
/// is wrong, and this tells you which derived value did it — without a rebuild
/// and without reading `fromDetail`.
class _Inspector extends StatelessWidget {
  final AppTheme theme;
  const _Inspector({required this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final tv = PlatformUtil.isTelevision;
    return SettingsSection(
      title: 'Derived',
      children: [
        _row(t, 'separation', [
          for (final f in SurfaceFamily.values)
            '${f.name}: ${t.surface.modelFor(f).name}',
        ].join('  ·  ')),
        _row(t, 'scrim', '${t.light.scrim.name} · extent '
            '${t.light.scrimExtent.toStringAsFixed(2)} · vignette '
            '${t.light.vignette.toStringAsFixed(2)}'),
        _row(t, 'artwork', '${t.art.frame.name} · grade '
            '${t.art.gradeFor(tv).name} · room '
            '${t.art.reactiveRoom.toStringAsFixed(2)}'),
        _row(t, 'focus', '${t.focus.expression.name} · '
            '${t.focus.widthFor(tv).toStringAsFixed(1)}px · scale '
            '${t.focus.scale} · lift ${t.focus.lift}'),
        _row(t, 'motion', '${t.motion.character.name} · base '
            '${t.motion.base.inMilliseconds}ms · entrance '
            '${t.motion.entranceFor(tv).name}'),
        _row(t, 'shape', 'scale ${t.shape.scale.toStringAsFixed(2)} · pill '
            '${t.shape.pill.toStringAsFixed(0)} · grain '
            '${t.shape.grainFor(tv).toStringAsFixed(2)}'),
        _row(t, 'wait / idle',
            '${t.wait.styleFor(tv).name} · ${t.idle.policyFor(tv).name}'
            ' · depth ${t.idle.depth}'),
        _row(t, 'feedback',
            'traversal ${t.sound.traversalFor(tv).name}'
            ' · activation ${t.sound.activation.name}'
            ' · haptic ${t.sound.hapticFor(tv, activation: false).name}'),
        _row(t, 'density', 'row ${t.density.rowHeight} · card '
            '${t.density.cardScale} · gutter ${t.density.pageGutter}'),
        // Contrast is the number people actually get wrong, so it is measured
        // here rather than left to be discovered on a device.
        _row(t, 'contrast', 'ink/ground '
            '${_ratio(t.core.tx, t.core.ground).toStringAsFixed(1)}:1  ·  '
            'accent/ground '
            '${_ratio(t.core.accent, t.core.ground).toStringAsFixed(1)}:1  ·  '
            'inkOn(accent) '
            '${_ratio(t.inkOn(t.core.accent), t.core.accent).toStringAsFixed(1)}:1'),
      ],
    );
  }

  Widget _row(AppTheme t, String k, String v) => SettingsInfoTile(
    icon: Icons.chevron_right_rounded,
    title: k,
    value: v,
  );

  static double _ratio(Color a, Color b) {
    final la = a.withValues(alpha: 1).computeLuminance();
    final lb = b.withValues(alpha: 1).computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}
