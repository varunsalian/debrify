import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_pane_parts.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_row.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_dependencies.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart'
    show StartupIptvStorage;
import 'package:flutter/material.dart';

class IptvSettingsTwoPaneListPanes {
  final IptvSettingsTwoPaneDependencies _deps;
  IptvSettingsTwoPaneListPanes(this._deps);
  IptvSettingsTwoPane get widget => _deps.widget();
  IptvSettingsTwoPaneSections get _sections => _deps.sections();

  Widget buildListsPane() {
    var row = 0;
    final lists = widget.customLists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.bookmark_rounded,
          title: 'Channel lists',
          meta:
              'Hold OK on any channel to add it to a list. '
              'Deleting a list never deletes its channels.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            // Nothing to configure — built in, can't be renamed, reordered or
            // deleted. Deliberately not a focus stop, and deliberately not
            // holding a pool slot.
            IptvTwoPaneRow(
              focusNode: null,
              icon: Icons.star_rounded,
              title: 'Favorites',
              subtitle: 'Built in · always available',
              trailing: null,
              onTap: null,
              onLeft: _sections.navigation.returnToRail,
            ),
            IptvTwoPaneRow(
              focusNode: _sections.navigation.paneNode(row++),
              icon: Icons.reorder_rounded,
              title: 'Channel order',
              subtitle: 'Arrange Favorites and saved lists',
              trailing: _sections.panes.chevron,
              onTap: widget.onManageChannelOrder,
              onLeft: _sections.navigation.returnToRail,
            ),
            for (var i = 0; i < lists.length; i++)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.bookmark_border_rounded,
                title: lists[i].name,
                subtitle:
                    '${lists[i].channelCount} channel'
                    '${lists[i].channelCount == 1 ? '' : 's'}',
                trailing: _sections.panes.chevron,
                onTap: () => widget.onListActions(lists[i]),
                onLeft: _sections.navigation.returnToRail,
              ),
            IptvTwoPaneRow(
              focusNode: _sections.navigation.paneNode(row++),
              icon: Icons.add_rounded,
              title: 'Create list',
              subtitle: null,
              trailing: _sections.panes.chevron,
              onTap: widget.onCreateList,
              onLeft: _sections.navigation.returnToRail,
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget buildStartupPane() {
    var row = 0;
    final pinned =
        widget.startupMode == StartupIptvStorage.startupIptvModePinned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.play_circle_outline_rounded,
          title: 'Startup channel',
          meta: 'Open straight into a live channel when the app starts.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            IptvTwoPaneRow(
              focusNode: _sections.navigation.paneNode(row++),
              icon: Icons.power_settings_new_rounded,
              title: 'Start on a channel',
              subtitle: 'Press BACK while it is tuning to stop',
              trailing: Switch(
                value: widget.startupEnabled,
                onChanged: widget.onToggleStartup,
              ),
              onTap: () => widget.onToggleStartup(!widget.startupEnabled),
              onLeft: _sections.navigation.returnToRail,
              isLast: !widget.startupEnabled,
            ),
            if (widget.startupEnabled) ...[
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.history_rounded,
                title: 'Last watched channel',
                // Honest about the bootstrap: the first boot after enabling
                // this has nothing to resume, and silently doing nothing
                // reads as broken.
                subtitle: widget.hasLastLiveChannel
                    ? 'Currently: ${widget.lastLiveChannelLabel}'
                    : 'Nothing watched yet — starts on the first channel, '
                          'then remembers what you watch.',
                trailing: Radio<String>(
                  value: StartupIptvStorage.startupIptvModeLast,
                  groupValue: widget.startupMode,
                  onChanged: (v) =>
                      v == null ? null : widget.onStartupModeChanged(v),
                ),
                onTap: () => widget.onStartupModeChanged(
                  StartupIptvStorage.startupIptvModeLast,
                ),
                onLeft: _sections.navigation.returnToRail,
              ),
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.push_pin_rounded,
                title: 'A specific channel',
                subtitle: widget.startupChannelLabel,
                trailing: Radio<String>(
                  value: StartupIptvStorage.startupIptvModePinned,
                  groupValue: widget.startupMode,
                  onChanged: (v) =>
                      v == null ? null : widget.onStartupModeChanged(v),
                ),
                onTap: () => widget.onStartupModeChanged(
                  StartupIptvStorage.startupIptvModePinned,
                ),
                onLeft: _sections.navigation.returnToRail,
                isLast: !pinned,
              ),
              if (pinned)
                IptvTwoPaneRow(
                  focusNode: _sections.navigation.paneNode(row++),
                  icon: Icons.live_tv_rounded,
                  title: widget.hasStartupChannel
                      ? 'Change channel'
                      : 'Choose channel',
                  subtitle: null,
                  trailing: _sections.panes.chevron,
                  onTap: widget.onPickStartupChannel,
                  onLeft: _sections.navigation.returnToRail,
                  isLast: true,
                ),
            ],
          ],
        ),
      ],
    );
  }
}
