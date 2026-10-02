import 'package:debrify/screens/settings/detail_page_style_page.dart';
import 'package:debrify/screens/settings/parents_guide_style_page.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice07 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice7() {
    return [
      // Settings SEARCH still finds it, deliberately.
      //
      // The row is gone from the Appearance list because a Look is the single
      // top-level choice now — but someone who knows the app has themes and
      // types "theme" should land somewhere, and the honest destination is the
      // Looks page rather than nothing at all.
      nav(
        SettingsRows.themeTokens,
        'Appearance',
        deps.openThemeTokensPage,
        subtitle: deps.themeTokensLabel(),
        keywords: [
          'advanced',
          'token',
          'colour',
          'color',
          'accent',
          'background',
          'font',
          'corner',
          'motion',
        ],
      ),
      nav(
        SettingsRows.looks,
        'Appearance',
        deps.openLooksPage,
        subtitle: AppLooks.active()?.label ?? 'Custom',
        keywords: [
          'app',
          'theme',
          'app theme',
          'whole app',
          'colour',
          'color',
          'palette',
          'look',
          'style',
          'skin',
          'dark',
          'light',
          'legacy',
          'classic',
          ...labels(AppLooks.all.map((look) => look.label)),
          'experimental',
          // Every theme by NAME, derived rather than typed out. The names used
          // to live on the Details Theme entry; withholding that row would
          // otherwise have made searching "velvet" or "deep field" find
          // nothing, and a hardcoded copy had already gone stale — it listed
          // the twenty old cores and none of the five new looks.
          for (final t in DetailThemes.catalogue) t.label.toLowerCase(),
        ],
      ),
      nav(
        SettingsRows.parentsGuideStyle,
        'Appearance',
        deps.openParentsGuideStylePage,
        subtitle: parentsGuideStyleLabel(summaries.parentsGuideStyle),
        keywords: [
          'parents',
          'parental',
          'guide',
          'advisory',
          'content rating',
          'severity',
          'compass',
          'classic',
          'family',
          ...labels(kParentsGuideStyleChoices.map((choice) => choice.label)),
        ],
      ),
      // Ungated: the details page opens on every platform.
      nav(
        SettingsRows.detailPageStyle,
        'Appearance',
        deps.openDetailPageStylePage,
        subtitle: detailPageStyleLabel(summaries.detailPageStyle),
        keywords: [
          'details',
          'detail',
          'page',
          'layout',
          'style',
          'theme',
          'look',
          'movie',
          'series',
          'show',
          'episodes',
          'episode list',
          'visible sections',
          'where to watch',
          'rent',
          'buy',
          'availability',
          'justwatch',
          'tmdb',
          'did you know',
          'trivia',
          'marquee',
          'dossier',
          'broadsheet',
          'stage',
          'filmstrip',
          'console',
          'classic',
          ...labels(kDetailPageStyleChoices.map((choice) => choice.label)),
        ],
      ),
      if (!PlatformUtil.isTelevision)
        nav(
          SettingsRows.navigationStyle,
          'Appearance',
          deps.openNavigationSettings,
          keywords: const [
            'navigation',
            'nav',
            'bottom bar',
            'tabs',
            'floating',
            'classic',
            'menu',
            'display',
            'home & display',
          ],
        ),

      nav(
        SettingsRows.player,
        'Playback',
        deps.openExternalPlayerSettings,
        keywords: [
          'external player',
          'video player',
          if (deps.isAndroid()) ...['system app chooser', 'vlc', 'mx player'],
          'subtitle',
          'subtitles',
          'audio track',
          'skip intro',
          'skip credits',
          'outro',
          'auto provider',
          'skipdb',
          'introdb',
          'theintrodb',
          'watch history',
          'watched',
          'completion',
          'threshold',
          'movie',
          'episode',
        ],
      ),
      nav(
        SettingsRows.remote,
        'Devices',
        deps.openRemoteControl,
        keywords: const [
          'cast',
          'handoff',
          'phone',
          'receive',
          'send',
          'setup',
        ],
      ),
    ];
  }
}
