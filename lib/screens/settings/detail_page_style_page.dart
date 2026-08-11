import '../../theme/app_looks.dart';
import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable look for the merged details page.
class DetailPageStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const DetailPageStyleChoice(this.value, this.label, this.subtitle);
}

/// Every look this build can actually draw.
///
/// Deliberately narrower than [StorageService.kDetailPageStyles], which accepts
/// every known value so a choice written by a newer build survives a downgrade. This set
/// grows as each layout lands; the picker lists only these, and dispatch, the
/// Settings row subtitle and the picker's own selected state all read
/// [effectiveDetailPageStyle] rather than the raw stored value — otherwise a
/// downgraded build would label a style it cannot render and show no selection.
const Set<String> kDetailPageStylesShipped = {
  'classic',
  'marquee',
  'dossier',
  'stage',
  'console',
  'vista',
  'monolith',
  'mosaic',
  'halo',
  'premiere',
  'showcase',
};

/// The stored value narrowed to what this build can render. Never persists —
/// the raw choice is left alone so upgrading restores it.
String effectiveDetailPageStyle(String raw) =>
    kDetailPageStylesShipped.contains(raw)
        ? raw
        : StorageService.kDetailPageStyleDefault;

const List<DetailPageStyleChoice> kDetailPageStyleChoices = [
  DetailPageStyleChoice(
    'showcase',
    'Showcase',
    'Full-bleed art that dissolves into a colour field; episodes, cast and '
        'sources as bands',
  ),
  DetailPageStyleChoice(
    'classic',
    'Classic',
    // No longer the default, and it is the one layout that ignores the app
    // theme — so the row says both rather than leaving someone to discover it.
    'The original — info beside a full-height episode list. Keeps its own '
        'look and ignores your App Theme.',
  ),
  DetailPageStyleChoice(
    'marquee',
    'Marquee',
    'Full-bleed artwork, the season as a row of wide episode cards',
  ),
  DetailPageStyleChoice(
    'dossier',
    'Dossier',
    'A fixed title card that never scrolls, beside a pure episode list',
  ),
  DetailPageStyleChoice(
    'broadsheet',
    'Broadsheet',
    'Editorial ink and serif — the season as a numbered ledger',
  ),
  DetailPageStyleChoice(
    'stage',
    'Stage',
    'Artwork on top, everything else in a tabbed deck below',
  ),
  DetailPageStyleChoice(
    'filmstrip',
    'Filmstrip',
    "The episode you're on fills the screen; the season runs along the bottom",
  ),
  DetailPageStyleChoice(
    'console',
    'Console',
    'Resume first — a big continue card, then the season as a grid',
  ),
  DetailPageStyleChoice(
    'vista',
    'Vista',
    'Cinematic artwork above a polished, glass-like episode shelf',
  ),
  DetailPageStyleChoice(
    'monolith',
    'Monolith',
    'A monumental title canvas beside a deep vertical season deck',
  ),
  DetailPageStyleChoice(
    'mosaic',
    'Mosaic',
    'Premium bento tiles for identity, metadata, guide and episodes',
  ),
  DetailPageStyleChoice(
    'halo',
    'Halo',
    'Centered cinematic identity with a luminous floating content dock',
  ),
  DetailPageStyleChoice(
    'premiere',
    'Premiere',
    'Editorial opening-night typography with an episode ledger',
  ),
];

/// Row caption for the current choice (Appearance row subtitle).
String detailPageStyleLabel(String style) {
  final effective = effectiveDetailPageStyle(style);
  for (final c in kDetailPageStyleChoices) {
    if (c.value == effective) return c.label;
  }
  return 'Classic';
}

/// Details-page look picker (`detail_page_style`).
///
/// The chosen layout applies to the movie/series details page everywhere it
/// opens. Read synchronously at build time from
/// [StorageService.detailPageStyleCached], so a change applies to the next time
/// the page is opened — persisting on tap is all that's needed.
class DetailPageStylePage extends StatefulWidget {
  const DetailPageStylePage({super.key});

  @override
  State<DetailPageStylePage> createState() => _DetailPageStylePageState();
}

class _DetailPageStylePageState extends State<DetailPageStylePage> {
  bool _loading = true;
  String _style = StorageService.kDetailPageStyleDefault;

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'detail-page-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  static List<DetailPageStyleChoice> get _choices => [
    for (final c in kDetailPageStyleChoices)
      if (kDetailPageStylesShipped.contains(c.value)) c,
  ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('detail_page_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getDetailPageStyle();
    if (!mounted) return;
    setState(() {
      // Narrowed, so a value this build can't draw still shows a selection.
      _style = effectiveDetailPageStyle(style);
      _loading = false;
    });
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Don't yank focus if it already landed on a real node (only the
        // route's FocusScope holds focus while nothing is focused yet).
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  Future<void> _select(String value) async {
    if (value == _style) return;
    setState(() => _style = value);
    // Tell an in-flight Look apply that a human just chose this key, so it
    // does not stamp over the choice. See theme/app_looks.dart.
    LookApplier.noteExternalWrite('detail_page_style');
    await StorageService.setDetailPageStyle(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Details Page',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Details Page',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.article_rounded,
                  title: 'Details Page',
                  subtitle:
                      'How a movie or series page is laid out when you open it',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in _choices) _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies the next time you open a movie or series — on this '
                  'device and on Android TV.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: t.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Radio-style row — a plain [SettingsTile] (the DPAD-proven row) with a
  /// check on the active one.
  Widget _optionRow(DetailPageStyleChoice choice) {
    final t = AppThemeScope.of(context).settings;
    final bool active = _style == choice.value;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.value),
    );
  }
}
