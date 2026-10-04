import 'package:debrify/features/iptv_settings/presentation/iptv_settings_playlist_tile.dart';
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_tv_tab_bar.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsSourceViewsDeps = ({
  IptvSettingsSourcesOwner sourcesOwner,
  IptvSettingsFocusOwner focusOwner,
  Future<void> Function(IptvPlaylist? playlist) setDefaultPlaylist,
  Future<void> Function(IptvPlaylist playlist) refreshPlaylist,
  Future<void> Function(IptvPlaylist playlist) editPlaylist,
  Future<void> Function(IptvPlaylist playlist) removePlaylist,
  BuildContext Function() context,
  IptvSettingsInputOwner inputOwner,
  void Function(FocusNode node) focusContentAfterTabSwitch,
  Widget Function() buildUrlTabContent,
  Widget Function() buildFileTabContent,
  Widget Function() buildXcTabContent,
});

class IptvSettingsSourceViews {
  IptvSettingsSourceViews(this._deps);
  final IptvSettingsSourceViewsDeps _deps;

  List<Widget> buildPlaylistsList() {
    final items = <Widget>[];

    for (int i = 0; i < _deps.sourcesOwner.playlists.length; i++) {
      final playlist = _deps.sourcesOwner.playlists[i];
      final isDefault = _deps.sourcesOwner.defaultPlaylistId == playlist.id;
      final starFocusIndex = i * 4;
      final refreshFocusIndex = i * 4 + 1;
      final editFocusIndex = i * 4 + 2;
      final deleteFocusIndex = i * 4 + 3;
      // URL and Xtream Codes playlists can be re-fetched; local files cannot.
      final canRefresh = !playlist.isLocalFile && !playlist.connectionReadOnly;

      items.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(5.0 + i),
          child: IptvSettingsPlaylistTile(
            playlist: playlist,
            isDefault: isDefault,
            isRefreshing: _deps.sourcesOwner.refreshingIds.contains(
              playlist.id,
            ),
            starFocusNode:
                starFocusIndex < _deps.focusOwner.playlistFocusNodes.length
                ? _deps.focusOwner.playlistFocusNodes[starFocusIndex]
                : null,
            refreshFocusNode:
                refreshFocusIndex < _deps.focusOwner.playlistFocusNodes.length
                ? _deps.focusOwner.playlistFocusNodes[refreshFocusIndex]
                : null,
            editFocusNode:
                editFocusIndex < _deps.focusOwner.playlistFocusNodes.length
                ? _deps.focusOwner.playlistFocusNodes[editFocusIndex]
                : null,
            deleteFocusNode:
                deleteFocusIndex < _deps.focusOwner.playlistFocusNodes.length
                ? _deps.focusOwner.playlistFocusNodes[deleteFocusIndex]
                : null,
            onSetDefault: () =>
                _deps.setDefaultPlaylist(isDefault ? null : playlist),
            onRefresh: canRefresh
                ? () => _deps.refreshPlaylist(playlist)
                : null,
            onEdit: playlist.connectionReadOnly
                ? null
                : () => _deps.editPlaylist(playlist),
            onDelete: playlist.connectionReadOnly
                ? null
                : () => _deps.removePlaylist(playlist),
          ),
        ),
      );
    }

    return items;
  }

  Widget buildSourcesView() {
    final t = AppThemeScope.of(_deps.context()).settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Add Playlist section with Tabs
        const SettingsSectionLabel('Add Playlist'),
        const SizedBox(height: 6),

        // Tab bar
        IptvSettingsTvTabBar(
          tabController: _deps.inputOwner.tabController,
          urlTabFocusNode: _deps.focusOwner.urlTabFocusNode,
          fileTabFocusNode: _deps.focusOwner.fileTabFocusNode,
          xcTabFocusNode: _deps.focusOwner.xcTabFocusNode,
          onUpArrow: () => _deps.focusOwner.backButtonFocusNode.requestFocus(),
          onDownArrowFromUrlTab: () => _deps.focusContentAfterTabSwitch(
            _deps.focusOwner.nameInputFocusNode,
          ),
          onDownArrowFromFileTab: () => _deps.focusContentAfterTabSwitch(
            _deps.focusOwner.importFileButtonFocusNode,
          ),
          onDownArrowFromXcTab: () => _deps.focusContentAfterTabSwitch(
            _deps.focusOwner.xcNameFocusNode,
          ),
        ),
        const SizedBox(height: 16),

        // Tab content (fixed height container). Sized for the tallest
        // tab — Xtream Login's four fields + button since the optional
        // name field joined (From URL has three fields + button); at 260
        // the button overflowed the box (painted-but-unclipped in release,
        // overlapping the section below).
        SizedBox(
          height: 410,
          child: TabBarView(
            controller: _deps.inputOwner.tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Off-screen tab pages stay built by TabBarView, so exclude
              // them from focus or DPAD traversal can land on invisible
              // fields/buttons (a dead zone on TV).
              ExcludeFocus(
                excluding: _deps.inputOwner.tabController.index != 0,
                child: _deps.buildUrlTabContent(),
              ),
              ExcludeFocus(
                excluding: _deps.inputOwner.tabController.index != 1,
                child: _deps.buildFileTabContent(),
              ),
              ExcludeFocus(
                excluding: _deps.inputOwner.tabController.index != 2,
                child: _deps.buildXcTabContent(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Playlists list
        const SettingsSectionLabel('Your Playlists'),
        Text(
          'Tap the star to set a default playlist.',
          style: TextStyle(fontSize: 12, color: t.dim),
        ),
        const SizedBox(height: 16),

        if (_deps.sourcesOwner.playlists.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.playlist_add, size: 48, color: t.dim2),
                  const SizedBox(height: 12),
                  Text(
                    'No playlists yet',
                    style: TextStyle(fontSize: 14, color: t.dim),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add an M3U playlist URL above',
                    style: TextStyle(fontSize: 12, color: t.dim2),
                  ),
                ],
              ),
            ),
          )
        else
          Card(child: Column(children: buildPlaylistsList())),
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
