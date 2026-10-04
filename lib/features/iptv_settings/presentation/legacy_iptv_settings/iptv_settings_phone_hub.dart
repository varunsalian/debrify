import 'dart:async' show unawaited;

import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsPhoneHubDeps = ({
  List<IptvPlaylist> Function() hideableSources,
  IptvSettingsSourcesOwner sourcesOwner,
  IptvSettingsFocusOwner focusOwner,
  void Function(IptvSettingsPhoneSection section) enterPhoneSection,
  IptvSettingsPreferencesOwner preferencesOwner,
  Future<void> Function() pickAutoRefresh,
  List<IptvListMeta> Function() customLists,
  Future<void> Function() openChannelOrder,
  List<IptvPlaylist> Function() categoryOrderSources,
  String Function() startupChannelLabel,
  bool Function() appearanceVisible,
  Future<void> Function() openIptvStylePicker,
  Future<void> Function() openPlayerGuidePicker,
  IptvSettingsRecordingOwner recordingOwner,
});

class IptvSettingsPhoneHub {
  IptvSettingsPhoneHub(this._deps);
  final IptvSettingsPhoneHubDeps _deps;

  /// The narrow layout's first screen: one row per destination, mirroring
  /// the wide layout's rail. Every row quotes its live state so the hub
  /// reads as a summary, not a menu.
  Widget buildPhoneHub() {
    // Sum only sources that still exist — a deleted source's cached count
    // must not haunt the subtitle.
    final hideableIds = {for (final p in _deps.hideableSources()) p.id};
    final hiddenTotal = _deps.sourcesOwner.hiddenCounts.entries
        .where((e) => hideableIds.contains(e.key))
        .fold(0, (a, e) => a + e.value);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SettingsPageHeader(
          icon: Icons.live_tv_rounded,
          title: 'IPTV Playlists',
          subtitle:
              'Sources, lists, startup and looks — everything IPTV in one '
              'place.',
        ),
        const SizedBox(height: 24),
        SettingsSection(
          title: '',
          children: [
            SettingsTile(
              focusNode: _deps.focusOwner.hubSourcesFocusNode,
              icon: Icons.playlist_play_rounded,
              title: 'Sources',
              subtitle: _deps.sourcesOwner.playlists.isEmpty
                  ? 'None yet — add your first playlist'
                  : '${_deps.sourcesOwner.playlists.length} '
                        '${_deps.sourcesOwner.playlists.length == 1 ? 'source' : 'sources'}',
              onTap: () async =>
                  _deps.enterPhoneSection(IptvSettingsPhoneSection.sources),
            ),
            SettingsTile(
              icon: Icons.update_rounded,
              title: 'Auto-refresh',
              subtitle:
                  '${iptvAutoRefreshLabel(_deps.preferencesOwner.autoRefreshHours)} · All sources in this profile',
              onTap: _deps.pickAutoRefresh,
            ),
            SettingsTile(
              icon: Icons.video_library_rounded,
              title: 'Channel lists',
              subtitle: _deps.customLists().isEmpty
                  ? 'Favorites only'
                  : 'Favorites + ${_deps.customLists().length} '
                        '${_deps.customLists().length == 1 ? 'list' : 'lists'}',
              onTap: () async =>
                  _deps.enterPhoneSection(IptvSettingsPhoneSection.lists),
            ),
            SettingsTile(
              icon: Icons.reorder_rounded,
              title: 'Channel order',
              subtitle: 'Arrange Favorites and saved lists',
              onTap: _deps.openChannelOrder,
            ),
            if (_deps.categoryOrderSources().isNotEmpty)
              SettingsTile(
                icon: Icons.swap_vert_rounded,
                title: 'Category order',
                subtitle: 'Arrange categories by source',
                onTap: () async => _deps.enterPhoneSection(
                  IptvSettingsPhoneSection.categoryOrder,
                ),
              ),
            if (_deps.hideableSources().isNotEmpty)
              SettingsTile(
                icon: Icons.visibility_off_rounded,
                title: 'Hidden categories',
                subtitle: hiddenTotal == 0
                    ? 'Nothing hidden'
                    : '$hiddenTotal '
                          '${hiddenTotal == 1 ? 'category' : 'categories'} '
                          'hidden',
                onTap: () async =>
                    _deps.enterPhoneSection(IptvSettingsPhoneSection.hidden),
              ),
            SettingsTile(
              icon: Icons.rocket_launch_rounded,
              title: 'Startup',
              subtitle: !_deps.preferencesOwner.startupEnabled
                  ? 'Off'
                  : _deps.preferencesOwner.startupMode ==
                        StartupIptvStorage.startupIptvModeLast
                  ? 'Last watched channel'
                  : _deps.startupChannelLabel(),
              onTap: () async =>
                  _deps.enterPhoneSection(IptvSettingsPhoneSection.startup),
            ),
            SettingsTile(
              icon: Icons.ondemand_video_rounded,
              title: 'Channel preview',
              subtitle: _deps.preferencesOwner.channelPreviewEnabled
                  ? 'On · uses a provider stream while browsing'
                  : 'Off · no stream until you press Watch',
              onTap: () async => _deps.enterPhoneSection(
                IptvSettingsPhoneSection.channelPreview,
              ),
            ),
            SettingsTile(
              icon: Icons.history_toggle_off_rounded,
              title: 'Continue watching',
              subtitle: _deps.preferencesOwner.trackContinueWatching
                  ? 'Tracking movies and series'
                  : 'Off',
              onTap: () async => _deps.enterPhoneSection(
                IptvSettingsPhoneSection.continueWatching,
              ),
            ),
            // The looks land on the same standalone pickers the Appearance
            // settings section uses — one implementation per pref.
            if (_deps.appearanceVisible())
              SettingsTile(
                icon: Icons.style_rounded,
                title: 'Appearance',
                subtitle: iptvStyleLabel(_deps.preferencesOwner.iptvStyle),
                onTap: () async => unawaited(_deps.openIptvStylePicker()),
              ),
            SettingsTile(
              icon: Icons.smart_display_rounded,
              title: 'Player guide',
              subtitle: playerGuideStyleLabel(
                _deps.preferencesOwner.playerGuideStyle,
              ),
              onTap: () async => unawaited(_deps.openPlayerGuidePicker()),
            ),
            if (_deps.recordingOwner.recordingSectionVisible)
              SettingsTile(
                icon: Icons.fiber_manual_record_rounded,
                title: 'Recording',
                subtitle: !_deps.recordingOwner.engineToggleVisible
                    ? (_deps.recordingOwner.scheduledCount == 0
                          ? 'Recordings'
                          : '${_deps.recordingOwner.scheduledCount} scheduled')
                    : _deps.recordingOwner.recordingEngineOn
                    ? (_deps.recordingOwner.scheduledCount == 0
                          ? 'Engine on'
                          : 'Engine on · ${_deps.recordingOwner.scheduledCount} scheduled')
                    : 'Player-tied',
                onTap: () async =>
                    _deps.enterPhoneSection(IptvSettingsPhoneSection.recording),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_deps.sourcesOwner.defaultPlaylistId != null)
          const SettingsInfoBanner(
            text:
                'Your default playlist will load automatically when you select IPTV.',
          ),
      ],
    );
  }
}
