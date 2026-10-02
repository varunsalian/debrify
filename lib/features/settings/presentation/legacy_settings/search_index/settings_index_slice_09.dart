import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice09 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice9() {
    return [
      // TV Mode
      nav(
        SettingsRows.debrifyTv,
        'Live TV & DVR',
        deps.openDebrifyTvSettings,
        keywords: const ['channels', 'limits', 'playback', 'android tv'],
      ),
      // One row, one entry: the recordings page owns the whole DVR — a second
      // "IPTV recording" entry pointed at the same page and only split the
      // keywords. The engine/battery/concurrency switches live in IPTV
      // settings instead, and are indexed as leaves there.
      nav(
        SettingsRows.recordings,
        'Live TV & DVR',
        deps.openRecordings,
        keywords: const [
          'record',
          'recording',
          'recordings',
          'dvr',
          'schedule',
          'scheduled',
          'timer',
          'rec',
          'library',
          'capture',
          'iptv',
          'live tv',
        ],
      ),
      nav(
        SettingsRows.iptvPlaylists,
        'Live TV & DVR',
        deps.openIptvSettings,
        keywords: const ['m3u', 'xtream', 'channels', 'epg', 'live tv'],
      ),
      // Reachable only from the Stremio TV screen's own gear — indexed so its
      // settings are findable where every other setting is. Categorised under
      // its own name, not a settings section it isn't a row of.
      SettingsSearchEntry(
        icon: Icons.smart_display_rounded,
        title: 'Stremio TV',
        subtitle: 'Rotation, quality, provider and playback for Stremio TV',
        category: 'Stremio TV',
        keywords: const [
          'stremio tv',
          'channel',
          'channels',
          'rotation',
          'series rotation',
          'random',
          'episodes',
          'quality',
          'debrid provider',
          'torrents first',
          'auto-refresh',
          'now playing',
          'start position',
        ],
        onTap: deps.openStremioTvSettings,
      ),
      SettingsSearchEntry(
        icon: SettingsRows.tvKeyboard.icon,
        title: SettingsRows.tvKeyboard.title,
        subtitle: SettingsRows.tvKeyboard.subtitle,
        category: 'Home & Display',
        keywords: const [
          'on-screen keyboard',
          'remote',
          'text input',
          'ime',
          'typing',
          // The mic key is a keyboard feature with no row of its own.
          'voice',
          'mic',
          'microphone',
          'dictation',
          'speak',
        ],
        toggleValue: () => summaries.tvKeyboardEnabled,
        onToggle: deps.toggleTvKeyboard,
      ),

      nav(
        SettingsRows.syncAndMigrate,
        'Sync and Migrate',
        deps.openSyncAndMigrate,
        keywords: const [
          'webdav',
          'migration',
          'transfer',
          'apple tv',
          'tvos',
          'encrypted',
        ],
      ),
    ];
  }
}
