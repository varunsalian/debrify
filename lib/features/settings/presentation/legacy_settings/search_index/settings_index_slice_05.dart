import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/screens/settings/desktop_sidebar_style_page.dart';
import 'package:debrify/screens/settings/discover_layout_page.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/tv_hero_artwork_quality_page.dart';
import 'package:debrify/screens/settings/tv_home_style_page.dart';
import 'package:debrify/screens/settings/tv_sidebar_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice05 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice5() {
    return [
      // Android TV + tvOS: this controls Flutter image decode bounds, so it is
      // independent of Android's native render-scale picker above.
      if (deps.isTelevision())
        nav(
          SettingsRows.tvHeroArtworkQuality,
          'Appearance',
          deps.openTvHeroArtworkQuality,
          subtitle: tvHeroArtworkQualityLabel(summaries.tvHeroArtworkQuality),
          keywords: [
            'hero',
            'artwork',
            'image',
            'picture',
            'poster',
            'backdrop',
            'quality',
            'resolution',
            '1080p',
            'full hd',
            'sharp',
            'memory',
            'performance',
            'home',
            'tv',
            ...labels(
              kTvHeroArtworkQualityChoices.map((choice) => choice.label),
            ),
          ],
        ),
      // Every platform now: TV picks among the eight layouts, phones and
      // desktop between Classic and Spotlight (the picker narrows itself).
      nav(
        SettingsRows.tvHomeStyle,
        'Appearance',
        deps.openTvHomeStyle,
        subtitle: tvHomeStyleLabel(
          summaries.isAndroidTv
              ? summaries.tvHomeStyle
              : effectiveOffTvHomeStyle(summaries.tvHomeStyle),
        ),
        keywords: [
          'home',
          'layout',
          'home screen',
          'canvas',
          'spotlight',
          'shelf',
          'classic',
          'rows',
          'redesign',
          'view',
          'display',
          'home & display',
          ...labels(
            (deps.isTelevision() ? kTvHomeStyleChoices : kOffTvHomeStyleChoices)
                .map((choice) => choice.label),
          ),
        ],
      ),
      nav(
        SettingsRows.profileAppearance,
        'Appearance',
        deps.openProfileAppearance,
        subtitle: ProfileGateStyle.labelFor(ProfileGateStyle.cached),
        keywords: [
          'profile',
          'picker',
          'who is watching',
          'who\'s watching',
          'marquee',
          'theater',
          'portrait wall',
          'top shelf',
          'personalized top shelf',
          'apple tv',
          ...labels(ProfileGateStyle.options.map((option) => option.label)),
        ],
      ),
      if (deps.isTelevision() ||
          MediaQuery.sizeOf(deps.context()).shortestSide >= 600 ||
          (PlatformUtil.isDesktop &&
              MediaQuery.sizeOf(deps.context()).width >= 600))
        nav(
          SettingsRows.collectionListStyle,
          'Appearance',
          deps.openCollectionListStyle,
          subtitle: 'Grid · Gallery · Filmstrip · Journal · Spotlight',
          keywords: [
            'collection',
            'list',
            'gallery',
            'filmstrip',
            'journal',
            'spotlight',
          ],
        ),
      if (summaries.isAndroidTv)
        nav(
          SettingsRows.discoverLayout,
          'Appearance',
          deps.openDiscoverLayout,
          subtitle: discoverLayoutLabel(summaries.discoverLayout),
          keywords: [
            'discover',
            'layout',
            'stage',
            'grid',
            'browse',
            'shelf',
            'catalog',
            'view',
            'posters',
            'display',
            'home & display',
            ...labels(kDiscoverLayoutChoices.map((choice) => choice.label)),
          ],
        ),
      // Android TV only — the rail is TV chrome.
      if (summaries.isAndroidTv)
        nav(
          SettingsRows.tvSidebarStyle,
          'Appearance',
          deps.openTvSidebarStyle,
          subtitle: tvSidebarStyleLabel(summaries.tvSidebarStyle),
          keywords: [
            'sidebar',
            'nav',
            'navigation',
            'rail',
            'menu',
            'ghost',
            'island',
            'marquee',
            'badge',
            'dock',
            'display',
            'home & display',
            'order and names',
            'rename sidebar',
            ...labels(kTvSidebarStyleChoices.map((choice) => choice.label)),
          ],
        ),
      // Desktop/tablet — the wide-window rail's own picker.
      if (!summaries.isAndroidTv && !PlatformUtil.isTelevision)
        nav(
          SettingsRows.desktopSidebarStyle,
          'Appearance',
          deps.openDesktopSidebarStyle,
          subtitle: desktopSidebarStyleLabel(summaries.desktopSidebarStyle),
          keywords: [
            'sidebar',
            'nav',
            'navigation',
            'rail',
            'menu',
            'pill',
            'desktop',
            'tablet',
            'ipad',
            'display',
            'home & display',
            'order and names',
            'rename sidebar',
            ...labels(
              kDesktopSidebarStyleChoices.map((choice) => choice.label),
            ),
          ],
        ),
    ];
  }
}
