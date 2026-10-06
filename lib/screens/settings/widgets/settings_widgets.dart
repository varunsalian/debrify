import 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_rows.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_tokens.dart';
import 'package:debrify/models/tv_render_quality.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:flutter/material.dart';

export 'package:debrify/features/settings_widgets/presentation/settings_connection_card.dart'
    show ConnectionCard, settingsInitialsFor;
export 'package:debrify/features/settings_widgets/presentation/settings_connection_info.dart'
    show
        ConnectionInfo,
        settingsConnectionIsReady,
        settingsConnectionNeedsAttention;
export 'package:debrify/features/settings_widgets/presentation/settings_connections_summary.dart'
    show ConnectionsSummary;
export 'package:debrify/features/settings_widgets/presentation/settings_links.dart'
    show launchSettingsUrl;
export 'package:debrify/features/settings_widgets/presentation/settings_look_hero.dart'
    show SettingsLookHero;
export 'package:debrify/features/settings_widgets/presentation/settings_page_chrome.dart'
    show
        SettingsBannerTone,
        SettingsInfoBanner,
        SettingsPageHeader,
        SettingsPageScaffold;
export 'package:debrify/features/settings_widgets/presentation/settings_page_theme.dart'
    show pushSettingsPage, settingsPageTheme, showSettingsDialog;
export 'package:debrify/features/settings_widgets/presentation/settings_pending_badge.dart'
    show WebDavSyncPendingBadge;
export 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart'
    show SettingsBackground, SettingsHeader, SettingsSectionLabel;
export 'package:debrify/features/settings_widgets/presentation/settings_rows.dart'
    show SettingsRowContent, SettingsRows;
export 'package:debrify/features/settings_widgets/presentation/settings_section.dart'
    show SettingsSection;
export 'package:debrify/features/settings_widgets/presentation/settings_tile.dart'
    show SettingsTile;
export 'package:debrify/features/settings_widgets/presentation/settings_toggle_tile.dart'
    show SettingsToggleTile;
export 'package:debrify/features/settings_widgets/presentation/settings_tokens.dart'
    show
        kSettingsAccent,
        kSettingsAccent2,
        kSettingsAmber,
        kSettingsBg,
        kSettingsDim,
        kSettingsDim2,
        kSettingsGreen,
        kSettingsLine,
        kSettingsMaxWidth,
        kSettingsPanel,
        kSettingsPanel2,
        kSettingsRed;

/// One Android TV "Screen Size" choice. [percent] is the share of the panel's
/// native density the UI is laid out at — smaller means a wider logical canvas,
/// so the same layouts draw smaller and more fits on screen. Values must stay in
/// step with `StorageService.kTvUiScaleOptions`; the shipped default is
/// `StorageService.kTvUiScaleDefault`.
///
/// Lives here (not in the TV settings shell) because two surfaces render it:
/// the TV Mode rail row's caption and the Screen Size page itself.
class TvUiScaleChoice {
  final int percent;
  final String title;
  final String subtitle;
  const TvUiScaleChoice(this.percent, this.title, this.subtitle);

  /// "Compact (80%)" — the row caption and the page's selected label.
  String get label => '$title ($percent%)';
}

const List<TvUiScaleChoice> kTvUiScaleChoices = [
  TvUiScaleChoice(100, 'Large', 'The original size — everything bigger'),
  TvUiScaleChoice(90, 'Medium', 'Default — about 10% more fits on screen'),
  TvUiScaleChoice(80, 'Compact', 'About 25% more fits on screen'),
];

/// Caption for [percent], falling back to the raw value if a stored size is
/// ever outside the offered set.
String tvUiScaleLabel(int percent) {
  for (final c in kTvUiScaleChoices) {
    if (c.percent == percent) return c.label;
  }
  return '$percent%';
}

/// One entry in the Android TV "Rendering" picker.
class TvRenderQualityChoice {
  final TvRenderQuality quality;
  final String label;
  final String subtitle;
  const TvRenderQualityChoice(this.quality, this.label, this.subtitle);
}

/// Automatic first: it's the default, and it's the only option that leaves the
/// device-capability call intact. The other two are named for the TRADE, not
/// for the mechanism — nobody browsing settings knows what a render buffer is,
/// but everybody knows which of "sharper" and "smoother" they want right now.
const List<TvRenderQualityChoice> kTvRenderQualityChoices = [
  TvRenderQualityChoice(
    TvRenderQuality.auto,
    'Automatic',
    "Default — Debrify picks based on this TV's graphics",
  ),
  TvRenderQualityChoice(
    TvRenderQuality.sharp,
    'Sharper picture',
    'Draw at the panel\'s full resolution',
  ),
  TvRenderQualityChoice(
    TvRenderQuality.fast,
    'Smoother navigation',
    'Draw at about 720p so scrolling stays fluid — text and art look softer',
  ),
];

/// Caption for [quality] — the settings row's subtitle and the picker's
/// selected label.
String tvRenderQualityLabel(TvRenderQuality quality) {
  for (final c in kTvRenderQualityChoices) {
    if (c.quality == quality) return c.label;
  }
  return 'Automatic';
}

/// One choice inside a [SettingsSelectDropdown].
class SettingsSelectOption {
  final String value;
  final String title;
  final String? subtitle;

  const SettingsSelectOption(this.value, this.title, [this.subtitle]);
}

/// Single-choice dropdown for settings cards — replaces the old
/// RadioListTile stacks (Post-Torrent Action, File Selection, …).
///
/// DPAD notes: the closed field is one focusable node (focus ring comes from
/// the themed `focusedBorder`); OK opens the menu, whose items take DPAD
/// focus natively, and BACK dismisses it. The selected option's subtitle is
/// echoed under the field so the descriptive copy isn't lost when closed.
class SettingsSelectDropdown extends StatelessWidget {
  final List<SettingsSelectOption> options;
  final String value;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  const SettingsSelectDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final SettingsSelectOption? selected = options
        .cast<SettingsSelectOption?>()
        .firstWhere((o) => o!.value == value, orElse: () => null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          focusNode: focusNode,
          // A stale stored value (e.g. removed option) renders as an empty
          // field instead of tripping DropdownButton's value assert.
          initialValue: selected?.value,
          isExpanded: true,
          // Variable item heights so subtitles fit in the open menu.
          itemHeight: null,
          dropdownColor: t.panel2,
          borderRadius: BorderRadius.circular(14),
          // No focusColor: with an InputDecoration the SDK swaps the fill
          // color for it on focus, which would blank the panel fill. Focus
          // is carried by the themed focusedBorder instead.
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.dim),
          decoration: const InputDecoration(),
          // Explicit color (not inherit): the dropdown renders its menu items
          // with this style directly, outside the page's DefaultTextStyle.
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          // Closed field shows just the title; the subtitle lives below.
          selectedItemBuilder: (context) => [
            for (final o in options)
              Align(alignment: Alignment.centerLeft, child: Text(o.title)),
          ],
          items: [
            for (final o in options)
              DropdownMenuItem<String>(
                value: o.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        o.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: o.value == value
                              ? t.accent2
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (o.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          o.subtitle!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: t.dim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        if (selected?.subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              selected!.subtitle!,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: t.dim),
            ),
          ),
        ],
      ],
    );
  }
}

/// Non-interactive key/value row (e.g. Version).
class SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const SettingsInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  factory SettingsInfoTile.spec(
    SettingsRowContent content, {
    Key? key,
    required String value,
  }) {
    return SettingsInfoTile(
      key: key,
      icon: content.icon,
      title: content.title,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          SizedBox(width: 34, child: Icon(icon, color: t.dim, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              // No color: inherits onSurface (Text Brightness).
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: app.fade(app.core.tx, 0.05),
              borderRadius: app.shape.br(8),
              border: Border.all(color: t.line),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading skeleton, restyled to the flat Stremio panels.
class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonHeader(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Shimmer(width: 140, height: 24),
        SizedBox(height: 10),
        Shimmer(width: 220, height: 13),
      ],
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection();

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Shimmer(width: 120, height: 12),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.line),
          ),
          child: Column(
            children: [
              const _SkeletonTile(),
              Divider(height: 1, color: t.line),
              const _SkeletonTile(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: const [
          Shimmer(
            width: 34,
            height: 34,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          SizedBox(width: 12),
          Expanded(child: Shimmer(height: 14)),
        ],
      ),
    );
  }
}

/// The "why is this install in legacy mode" dialog, opened from the Profiles
/// row on every settings layout.
///
/// This dialog IS the bug report. The one channel a television reporter
/// reliably has is a phone photo of the screen, so the captured reason —
/// including the error and its first stack frame on the unpredicted path —
/// is shown in full here rather than summarized. The reassurance lines are
/// as load-bearing as the diagnosis: legacy mode looks like data loss from
/// the couch, and it is precisely the opposite.
Future<void> showLegacyModeInfoDialog(BuildContext context) {
  final app = AppThemeScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: app.sheetSurface,
      title: const Text('Running in legacy mode'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ProfileBootstrap.legacyReasonSummary,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: app.core.tx,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your data is untouched — migration copies, never moves — and '
                'it retries automatically on every launch.\n\n'
                'If this keeps appearing, photograph this dialog and share it '
                'in the Discord: the text above identifies the cause.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: app.core.tx.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
