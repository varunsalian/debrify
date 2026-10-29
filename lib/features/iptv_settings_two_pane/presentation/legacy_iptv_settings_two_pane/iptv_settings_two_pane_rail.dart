import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_auto_refresh_dialog.dart'
    show iptvAutoRefreshLabel;
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_destination.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_rail_entry.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_dependencies.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart'
    show iptvStyleLabel;
import 'package:debrify/services/iptv_source_stats.dart'
    show IptvSourceStatsLoader;
import 'package:debrify/services/storage/startup_iptv_storage.dart'
    show StartupIptvStorage;
import 'package:flutter/material.dart';

class IptvSettingsTwoPaneRail {
  final IptvSettingsTwoPaneDependencies _deps;
  IptvSettingsTwoPaneRail(this._deps);
  IptvSettingsTwoPane get widget => _deps.widget();
  IptvSettingsTwoPaneOwners get _owners => _deps.owners;
  IptvSettingsTwoPaneSections get _sections => _deps.sections();

  // ---------------------------------------------------------------- rail

  Widget buildRail() {
    final t = _owners.app.settings;
    final width = MediaQuery.sizeOf(_deps.context()).width;
    return SizedBox(
      width: width >= 1400 ? 400 : 330,
      child: ValueListenableBuilder<IptvTwoPaneDest>(
        valueListenable: _owners.dest,
        builder: (context, dest, _) {
          final selected = _sections.navigation.selectedRailIndex;
          return ListView(
            controller: _owners.railScroll,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            children: [
              const IptvTwoPaneRailHeading('Sources'),
              for (var i = 0; i < widget.playlists.length; i++)
                IptvTwoPaneRailEntry(
                  focusNode: _owners.railNodes[i],
                  icon: iconFor(widget.playlists[i]),
                  title: widget.playlists[i].name,
                  subtitle: _railSubtitle(widget.playlists[i]),
                  selected: selected == i,
                  trailing: widget.defaultPlaylistId == widget.playlists[i].id
                      ? Icon(Icons.star_rounded, size: 18, color: t.warning)
                      : null,
                  busy: widget.refreshingIds.contains(widget.playlists[i].id),
                  onFocused: () =>
                      _owners.dest.value = _sections.navigation.destForRail(i),
                  onSelect: _sections.navigation.enterPane,
                  onUp: i == 0
                      ? null
                      : () => _sections.navigation.focusRailAt(i - 1),
                  onDown: () => _sections.navigation.focusRailAt(i + 1),
                  onRight: _sections.navigation.enterPane,
                ),
              if (widget.playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: Text(
                    'No sources yet.',
                    style: TextStyle(fontSize: 13, color: t.dim),
                  ),
                ),
              IptvTwoPaneRailEntry(
                focusNode: _owners.railNodes[widget.playlists.length],
                icon: Icons.add_rounded,
                title: 'Add a source',
                subtitle: 'URL, file, or Xtream login',
                selected: selected == widget.playlists.length,
                onFocused: () =>
                    _owners.dest.value = const IptvTwoPaneAddDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: widget.playlists.isEmpty
                    ? null
                    : () => _sections.navigation.focusRailAt(
                        widget.playlists.length - 1,
                      ),
                onDown: () => _sections.navigation.focusRailAt(
                  widget.playlists.length + 1,
                ),
                onRight: _sections.navigation.enterPane,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Container(height: 1, color: t.line),
              ),
              IptvTwoPaneRailEntry(
                focusNode: _owners.railNodes[widget.playlists.length + 1],
                icon: Icons.bookmark_rounded,
                title: 'Channel lists',
                subtitle: _listsSubtitle,
                selected: selected == widget.playlists.length + 1,
                chevron: true,
                onFocused: () =>
                    _owners.dest.value = const IptvTwoPaneListsDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: () =>
                    _sections.navigation.focusRailAt(widget.playlists.length),
                onDown: () => _sections.navigation.focusRailAt(
                  widget.playlists.length + 2,
                ),
                onRight: _sections.navigation.enterPane,
              ),
              IptvTwoPaneRailEntry(
                focusNode: _owners.railNodes[widget.playlists.length + 2],
                icon: Icons.play_circle_outline_rounded,
                title: 'Startup channel',
                subtitle: widget.startupEnabled
                    ? (widget.startupMode ==
                              StartupIptvStorage.startupIptvModePinned
                          ? 'On · a specific channel'
                          : 'On · last watched')
                    : 'Off',
                selected: selected == widget.playlists.length + 2,
                chevron: true,
                onFocused: () =>
                    _owners.dest.value = const IptvTwoPaneStartupDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: () => _sections.navigation.focusRailAt(
                  widget.playlists.length + 1,
                ),
                onDown: () => _sections.navigation.focusRailAt(
                  widget.playlists.length + 3,
                ),
                onRight: _sections.navigation.enterPane,
              ),
              IptvTwoPaneRailEntry(
                focusNode:
                    _owners.railNodes[_sections.navigation.channelPreviewIndex],
                icon: Icons.ondemand_video_rounded,
                title: 'Channel preview',
                subtitle: widget.channelPreviewEnabled
                    ? 'On · uses a stream while browsing'
                    : 'Off · fullscreen playback only',
                selected: selected == _sections.navigation.channelPreviewIndex,
                chevron: true,
                onFocused: () =>
                    _owners.dest.value = const IptvTwoPaneChannelPreviewDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: () => _sections.navigation.focusRailAt(
                  widget.playlists.length + 2,
                ),
                onDown: () => _sections.navigation.focusRailAt(
                  _sections.navigation.continueWatchingIndex,
                ),
                onRight: _sections.navigation.enterPane,
              ),
              IptvTwoPaneRailEntry(
                focusNode: _owners
                    .railNodes[_sections.navigation.continueWatchingIndex],
                icon: Icons.history_toggle_off_rounded,
                title: 'Continue watching',
                subtitle: widget.trackContinueWatching
                    ? 'Tracking movies and series'
                    : 'Off',
                selected:
                    selected == _sections.navigation.continueWatchingIndex,
                chevron: true,
                onFocused: () => _owners.dest.value =
                    const IptvTwoPaneContinueWatchingDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: () => _sections.navigation.focusRailAt(
                  _sections.navigation.channelPreviewIndex,
                ),
                onDown: () => _sections.navigation.focusRailAt(
                  widget.showAppearanceSection
                      ? _sections.navigation.appearanceIndex
                      : _sections.navigation.playerGuideIndex,
                ),
                onRight: _sections.navigation.enterPane,
              ),
              if (widget.showAppearanceSection)
                IptvTwoPaneRailEntry(
                  focusNode:
                      _owners.railNodes[_sections.navigation.appearanceIndex],
                  icon: Icons.style_rounded,
                  title: 'Appearance',
                  subtitle: iptvStyleLabel(widget.iptvStyle),
                  selected: selected == _sections.navigation.appearanceIndex,
                  chevron: true,
                  onFocused: () =>
                      _owners.dest.value = const IptvTwoPaneAppearanceDest(),
                  onSelect: _sections.navigation.enterPane,
                  onUp: () => _sections.navigation.focusRailAt(
                    _sections.navigation.continueWatchingIndex,
                  ),
                  onDown: () => _sections.navigation.focusRailAt(
                    _sections.navigation.playerGuideIndex,
                  ),
                  onRight: _sections.navigation.enterPane,
                ),
              IptvTwoPaneRailEntry(
                focusNode:
                    _owners.railNodes[_sections.navigation.playerGuideIndex],
                icon: Icons.smart_display_rounded,
                title: 'Player guide',
                subtitle: switch (widget.playerGuideStyle) {
                  'glass' => 'Cinema Glass',
                  'edition' => 'Midnight Edition',
                  'console' => 'Master Control',
                  _ => 'Classic',
                },
                selected: selected == _sections.navigation.playerGuideIndex,
                chevron: true,
                onFocused: () =>
                    _owners.dest.value = const IptvTwoPanePlayerGuideDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: () => _sections.navigation.focusRailAt(
                  widget.showAppearanceSection
                      ? _sections.navigation.appearanceIndex
                      : _sections.navigation.continueWatchingIndex,
                ),
                onDown: widget.showRecordingSection
                    ? () => _sections.navigation.focusRailAt(
                        _sections.navigation.recordingIndex,
                      )
                    : () => _sections.navigation.focusRailAt(
                        _sections.navigation.autoRefreshIndex,
                      ),
                onRight: _sections.navigation.enterPane,
              ),
              if (widget.showRecordingSection)
                IptvTwoPaneRailEntry(
                  focusNode:
                      _owners.railNodes[_sections.navigation.recordingIndex],
                  icon: Icons.fiber_manual_record_rounded,
                  title: 'Recording',
                  subtitle: !widget.showEngineToggle
                      ? (widget.scheduledCount == 0
                            ? 'Recordings'
                            : '${widget.scheduledCount} scheduled')
                      : widget.recordingEngineEnabled
                      ? (widget.scheduledCount == 0
                            ? 'Engine on'
                            : 'Engine on · ${widget.scheduledCount} scheduled')
                      : 'Player-tied',
                  selected: selected == _sections.navigation.recordingIndex,
                  chevron: true,
                  onFocused: () =>
                      _owners.dest.value = const IptvTwoPaneRecordingDest(),
                  onSelect: _sections.navigation.enterPane,
                  onUp: () => _sections.navigation.focusRailAt(
                    _sections.navigation.playerGuideIndex,
                  ),
                  onDown: () => _sections.navigation.focusRailAt(
                    _sections.navigation.autoRefreshIndex,
                  ),
                  onRight: _sections.navigation.enterPane,
                ),
              IptvTwoPaneRailEntry(
                focusNode:
                    _owners.railNodes[_sections.navigation.autoRefreshIndex],
                icon: Icons.update_rounded,
                title: 'Auto-refresh',
                subtitle: iptvAutoRefreshLabel(widget.autoRefreshHours),
                selected: selected == _sections.navigation.autoRefreshIndex,
                chevron: true,
                onFocused: () =>
                    _owners.dest.value = const IptvTwoPaneAutoRefreshDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: () => _sections.navigation.focusRailAt(
                  widget.showRecordingSection
                      ? _sections.navigation.recordingIndex
                      : _sections.navigation.playerGuideIndex,
                ),
                onDown: () => _sections.navigation.focusRailAt(
                  _sections.navigation.sportsIndex,
                ),
                onRight: _sections.navigation.enterPane,
              ),
              IptvTwoPaneRailEntry(
                focusNode: _owners.railNodes[_sections.navigation.sportsIndex],
                icon: Icons.emoji_events_rounded,
                title: 'Sports & leagues',
                subtitle: 'What the Sports board shows',
                selected: selected == _sections.navigation.sportsIndex,
                chevron: true,
                onFocused: () =>
                    _owners.dest.value = const IptvTwoPaneSportsDest(),
                onSelect: _sections.navigation.enterPane,
                onUp: () => _sections.navigation.focusRailAt(
                  _sections.navigation.autoRefreshIndex,
                ),
                onDown: null,
                onRight: _sections.navigation.enterPane,
              ),
            ],
          );
        },
      ),
    );
  }

  String get _listsSubtitle {
    final n = widget.customLists.length;
    if (n == 0) return 'Favorites only';
    return 'Favorites + $n list${n == 1 ? '' : 's'}';
  }

  IconData iconFor(IptvPlaylist p) {
    if (p.isXtreamCodes) return Icons.dns_rounded;
    if (p.isLocalFile) return Icons.folder_rounded;
    return Icons.playlist_play_rounded;
  }

  String _railSubtitle(IptvPlaylist p) {
    final stats = _owners.sourceStats[p.id];
    final kind = p.isXtreamCodes
        ? 'Xtream'
        : (p.isLocalFile ? 'Local file' : 'URL');
    if (stats == null || !stats.cached) return kind;
    final live = IptvSourceStatsLoader.count(stats.live);
    return '$kind · $live channel${stats.live == 1 ? '' : 's'}';
  }
}
