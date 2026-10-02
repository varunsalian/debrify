import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice08 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice8() {
    return [
      // Search
      nav(
        SettingsRows.searchSettings,
        'Search',
        deps.openTorrentSettings,
        keywords: const ['engines', 'sorting', 'torrent', 'sources'],
      ),
      nav(
        SettingsRows.filterSettings,
        'Search',
        deps.openFilterSettings,
        keywords: const [
          'quality',
          'resolution',
          '1080p',
          '4k',
          '2160p',
          'hdr',
          'language',
          'codec',
          'hevc',
          'sdr',
          'dolby vision',
          'dynamic range',
        ],
      ),
      nav(
        SettingsRows.providerSettings,
        'Search',
        deps.openProviderSettings,
        keywords: const [
          'default provider',
          'add torrent',
          'debrid',
          'ask every time',
          'show provider selection dialog',
          'torbox',
          'real-debrid',
          'premiumize',
          'alldebrid',
          'pikpak',
        ],
      ),
      nav(
        SettingsRows.quickPlay,
        'Search',
        deps.openQuickPlaySettings,
        keywords: const ['instant', 'auto play', 'one tap'],
      ),
      nav(
        SettingsRows.discoverDefault,
        'Discover',
        deps.openDiscoverSettings,
        keywords: const [
          'remember last',
          'default source',
          'continue watching',
          'trakt',
          'simkl',
          'stremio addon',
          'movie tag',
          'series tag',
          'ratings',
          'poster titles',
          'hide titles',
        ],
      ),
      // "addon" was a settings search dead end. This is NOT a settings page,
      // so it opens the Addons TAB (the house switchTab idiom) rather than
      // pushing a page: the tab resolves the hub-vs-classic flag itself, and
      // the standalone `StremioAddonsPage`/`EngineImportPage` wrappers are
      // stale duplicates of the tab bodies that nothing else renders.
      // Its own category, because it does not live in a settings section.
      SettingsSearchEntry(
        icon: Icons.extension_rounded,
        title: 'Addons',
        subtitle: 'Stremio addons and torrent search engines',
        category: 'Addons',
        keywords: const [
          'addon',
          'addons',
          'stremio',
          'manifest',
          'install',
          'catalog',
          'catalogs',
          'subtitles',
          'torrentio',
          'marketplace',
          'engine',
          'engines',
          'import',
          'yaml',
          'add engine',
          'import from file',
          'remove addon',
          'delete all addons',
          'view details',
          'resources',
          'id prefixes',
          'last checked',
        ],
        onTap: () async => MainPageBridge.switchTab?.call(MainTab.addons),
      ),
    ];
  }
}
