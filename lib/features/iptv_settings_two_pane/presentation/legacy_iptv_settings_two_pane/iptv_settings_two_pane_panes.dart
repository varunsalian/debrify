import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_auto_refresh_dialog.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_destination.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_method_card.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_pane_parts.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_row.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_dependencies.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_source_stats.dart'
    show IptvGuideSource, IptvSourceStats, IptvSourceStatsLoader;
import 'package:flutter/material.dart';

class IptvSettingsTwoPanePanes {
  final IptvSettingsTwoPaneDependencies _deps;
  IptvSettingsTwoPanePanes(this._deps);
  IptvSettingsTwoPane get widget => _deps.widget();
  IptvSettingsTwoPaneOwners get _owners => _deps.owners;
  IptvSettingsTwoPaneSections get _sections => _deps.sections();

  // ---------------------------------------------------------------- pane

  Widget buildPane(IptvTwoPaneDest dest) {
    final child = switch (dest) {
      IptvTwoPaneSourceDest(:final playlistId) => _buildSourcePane(playlistId),
      IptvTwoPaneAddDest() => _buildAddPane(),
      IptvTwoPaneListsDest() => _sections.listPanes.buildListsPane(),
      IptvTwoPaneStartupDest() => _sections.listPanes.buildStartupPane(),
      IptvTwoPaneChannelPreviewDest() =>
        _sections.preferencePanes.buildChannelPreviewPane(),
      IptvTwoPaneContinueWatchingDest() =>
        _sections.preferencePanes.buildContinueWatchingPane(),
      IptvTwoPaneAppearanceDest() =>
        _sections.preferencePanes.buildAppearancePane(),
      IptvTwoPanePlayerGuideDest() =>
        _sections.preferencePanes.buildPlayerGuidePane(),
      IptvTwoPaneRecordingDest() =>
        _sections.preferencePanes.buildRecordingPane(),
      IptvTwoPaneAutoRefreshDest() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IptvTwoPanePaneHeader(
            icon: Icons.update_rounded,
            title: 'Auto-refresh',
            meta: 'All sources in this profile',
            badges: [],
          ),
          const SizedBox(height: 24),
          IptvTwoPaneRow(
            focusNode: _owners.paneNodes[0],
            icon: Icons.schedule_rounded,
            title: iptvAutoRefreshLabel(widget.autoRefreshHours),
            subtitle: iptvAutoRefreshExplanation,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onPickAutoRefresh,
            onLeft: () => _sections.navigation.focusRailAt(
              _sections.navigation.autoRefreshIndex,
            ),
          ),
        ],
      ),
    };
    // A key per destination gives each view its own scroll position, so
    // arriving from a scrolled-down Channel lists doesn't drop you into a
    // source with its header already off-screen.
    return ListView(
      key: ValueKey(switch (dest) {
        IptvTwoPaneSourceDest(:final playlistId) => 'source:$playlistId',
        IptvTwoPaneAddDest() => 'add',
        IptvTwoPaneListsDest() => 'lists',
        IptvTwoPaneStartupDest() => 'startup',
        IptvTwoPaneChannelPreviewDest() => 'channel-preview',
        IptvTwoPaneContinueWatchingDest() => 'continue-watching',
        IptvTwoPaneAppearanceDest() => 'appearance',
        IptvTwoPanePlayerGuideDest() => 'player_guide',
        IptvTwoPaneRecordingDest() => 'recording',
        IptvTwoPaneAutoRefreshDest() => 'auto-refresh',
      }),
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
      children: [child],
    );
  }

  Widget _buildSourcePane(String playlistId) {
    final t = _owners.app.settings;
    // Deleting the last source can leave one frame pointing here before
    // didUpdateWidget re-homes the pane; `.first` on an empty list would
    // throw rather than just render nothing.
    if (widget.playlists.isEmpty) return _buildAddPane();
    final playlist = widget.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => widget.playlists.first,
    );
    final stats =
        _owners.sourceStats[playlist.id] ?? const IptvSourceStats.none();
    final isDefault = widget.defaultPlaylistId == playlist.id;
    final busy = widget.refreshingIds.contains(playlist.id);
    // Local files have no remote to re-fetch.
    final canRefresh = !playlist.isLocalFile && !playlist.connectionReadOnly;

    var row = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IptvTwoPanePaneHeader(
          icon: _sections.rail.iconFor(playlist),
          title: playlist.name,
          meta: _sourceMeta(playlist),
          badges: [
            if (isDefault)
              IptvTwoPaneBadge('Default', t.warning, Icons.star_rounded),
            if (stats.guide == IptvGuideSource.custom)
              IptvTwoPaneBadge(
                'Custom guide',
                t.accent2,
                Icons.event_note_rounded,
              ),
            if (stats.guide == IptvGuideSource.provider)
              IptvTwoPaneBadge(
                'Provider guide',
                t.success,
                Icons.event_available_rounded,
              ),
            if (stats.cached && stats.refreshedAt != null)
              IptvTwoPaneBadge(
                'Refreshed ${IptvSourceStatsLoader.ago(stats.refreshedAt)}',
                t.accent2,
                Icons.schedule_rounded,
              ),
            if (playlist.connectionReadOnly)
              IptvTwoPaneBadge('Shared', t.accent2, Icons.lock_outline_rounded),
          ],
        ),
        const SizedBox(height: 20),
        if (stats.cached)
          IptvTwoPaneStatStrip(
            stats: [
              ('Live channels', IptvSourceStatsLoader.count(stats.live)),
              if (stats.hasVodSplit)
                ('Movies', IptvSourceStatsLoader.count(stats.movies)),
              if (stats.hasVodSplit)
                ('Series', IptvSourceStatsLoader.count(stats.series)),
              if (!stats.hasVodSplit)
                ('Categories', IptvSourceStatsLoader.count(stats.categories)),
            ],
          )
        else
          IptvTwoPaneQuietBanner(
            icon: playlist.isLocalFile
                ? Icons.sd_card_rounded
                : Icons.cloud_off_rounded,
            // "Not loaded yet" and "0 channels" are different facts; never
            // render the first as the second.
            text: playlist.isLocalFile
                ? 'Imported from a file — it plays from the copy stored in the app.'
                : 'Not loaded yet. Open this source in IPTV, or refresh it here.',
          ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            if (canRefresh)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.refresh_rounded,
                title: busy ? 'Refreshing…' : 'Refresh now',
                subtitle: 'Re-fetch channels and rebuild the catalog',
                trailing: Text(
                  stats.refreshedAt == null
                      ? 'never'
                      : IptvSourceStatsLoader.ago(stats.refreshedAt),
                  style: TextStyle(fontSize: 12.5, color: t.dim),
                ),
                // Stays focusable while busy, with the tap neutered — going
                // non-focusable mid-refresh would yank the focus out from
                // under the user who just pressed OK on it. Same idiom as
                // _TvFocusableButton's `_isAdding ? () {} : ...`.
                onTap: busy ? () {} : () => widget.onRefresh(playlist),
                onLeft: _sections.navigation.returnToRail,
              ),
            IptvTwoPaneRow(
              focusNode: _sections.navigation.paneNode(row++),
              icon: Icons.star_rounded,
              title: 'Default playlist',
              subtitle: 'Loads automatically when you open IPTV',
              trailing: Switch(
                value: isDefault,
                onChanged: (_) => widget.onSetDefault(playlist),
              ),
              onTap: () => widget.onSetDefault(playlist),
              onLeft: _sections.navigation.returnToRail,
            ),
            if (!playlist.connectionReadOnly)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.edit_rounded,
                title: 'Edit source',
                subtitle: playlist.isXtreamCodes
                    ? 'Name, server, username, password'
                    : 'Name, URL and guide URL',
                trailing: chevron,
                onTap: () => widget.onEdit(playlist),
                onLeft: _sections.navigation.returnToRail,
              ),
            // Imported files store no catalog, so there is nothing to hide
            // categories against — the row stays off them entirely.
            if (widget.onManageHidden != null && !playlist.isLocalFile)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.visibility_off_rounded,
                title: 'Hidden categories',
                subtitle: switch (widget.hiddenCounts[playlist.id] ?? 0) {
                  0 => 'Nothing hidden from this source',
                  1 => '1 category hidden',
                  final n => '$n categories hidden',
                },
                trailing: chevron,
                onTap: () => widget.onManageHidden!(playlist),
                onLeft: _sections.navigation.returnToRail,
              ),
            if (widget.onManageCategoryOrder != null)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.swap_vert_rounded,
                title: 'Category order',
                subtitle: 'Arrange categories in this source',
                trailing: chevron,
                onTap: () => widget.onManageCategoryOrder!(playlist),
                onLeft: _sections.navigation.returnToRail,
              ),
            if (!playlist.connectionReadOnly)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.event_note_rounded,
                title: 'Guide (EPG) source',
                subtitle: switch (stats.guide) {
                  IptvGuideSource.custom =>
                    'Custom XMLTV URL set for this source',
                  IptvGuideSource.provider =>
                    "Using the provider's own guide data",
                  IptvGuideSource.none =>
                    'No guide source — rows show no programmes',
                },
                trailing: chevron,
                onTap: () => widget.onEdit(playlist),
                onLeft: _sections.navigation.returnToRail,
              ),
            if (!playlist.connectionReadOnly)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.delete_outline_rounded,
                title: 'Remove source',
                subtitle: 'Keeps your lists and watch history',
                danger: true,
                trailing: chevron,
                onTap: () => widget.onDelete(playlist),
                onLeft: _sections.navigation.returnToRail,
                isLast: true,
              ),
          ],
        ),
      ],
    );
  }

  String _sourceMeta(IptvPlaylist p) {
    if (p.credentialsRedacted) {
      return 'Shared connection · credentials hidden';
    }
    if (p.isXtreamCodes) {
      final user = (p.username ?? '').isEmpty ? '' : ' · ${p.username}';
      return 'Xtream Codes · ${p.serverUrl ?? ''}$user';
    }
    if (p.isLocalFile) return 'Local file';
    return p.url;
  }

  Widget _buildAddPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.add_rounded,
          title: 'Add a source',
          meta: 'Pick how you want to connect, then fill in the details.',
          badges: [],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: IptvTwoPaneMethodCard(
                focusNode: widget.urlMethodFocusNode,
                icon: Icons.link_rounded,
                label: 'From URL',
                hint: 'An M3U or M3U8 link',
                selected: widget.addMethod == 0,
                onTap: () => widget.onAddMethodChanged(0),
                // Leftmost card: LEFT leaves the pane entirely.
                onLeft: _sections.navigation.returnToRail,
                onRight: widget.fileMethodFocusNode.requestFocus,
                onDown: widget.onFocusFirstFormField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: IptvTwoPaneMethodCard(
                focusNode: widget.fileMethodFocusNode,
                icon: Icons.folder_open_rounded,
                label: 'From file',
                hint: 'A file on this device',
                selected: widget.addMethod == 1,
                onTap: () => widget.onAddMethodChanged(1),
                onLeft: widget.urlMethodFocusNode.requestFocus,
                onRight: widget.xtreamMethodFocusNode.requestFocus,
                onDown: widget.onFocusFirstFormField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: IptvTwoPaneMethodCard(
                focusNode: widget.xtreamMethodFocusNode,
                icon: Icons.vpn_key_rounded,
                label: 'Xtream login',
                hint: 'Server, user, password',
                selected: widget.addMethod == 2,
                onTap: () => widget.onAddMethodChanged(2),
                onLeft: widget.fileMethodFocusNode.requestFocus,
                onRight: null,
                onDown: widget.onFocusFirstFormField,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        // Only the chosen method is built, so DPAD can never land on a
        // hidden field — the old fixed-height TabBarView kept all three
        // alive and had to ExcludeFocus the other two.
        switch (widget.addMethod) {
          1 => widget.fileFormBuilder(_deps.context()),
          2 => widget.xtreamFormBuilder(_deps.context()),
          _ => widget.urlFormBuilder(_deps.context()),
        },
      ],
    );
  }

  Widget get chevron => Icon(
    Icons.chevron_right_rounded,
    size: 20,
    color: _owners.app.settings.dim2,
  );
}
