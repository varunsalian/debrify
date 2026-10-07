import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_pane_parts.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_row.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_dependencies.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart'
    show kIptvStyleChoices;
import 'package:flutter/material.dart';

class IptvSettingsTwoPanePreferencePanes {
  final IptvSettingsTwoPaneDependencies _deps;
  IptvSettingsTwoPanePreferencePanes(this._deps);
  IptvSettingsTwoPane get widget => _deps.widget();
  IptvSettingsTwoPaneSections get _sections => _deps.sections();

  Widget buildContinueWatchingPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.history_toggle_off_rounded,
          title: 'Continue watching',
          meta:
              'The shelf of on-demand movies and series you have started, '
              'on Home and in IPTV.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            IptvTwoPaneRow(
              focusNode: _sections.navigation.paneNode(0),
              icon: Icons.playlist_add_check_rounded,
              title: 'Track movies and series',
              // Says what stays behind, because "off" reading as "my resume
              // positions are gone" is the obvious wrong guess here.
              subtitle:
                  'Off hides the shelf and stops adding to it. Nothing '
                  'is deleted, and playback still resumes where you left off',
              trailing: Switch(
                value: widget.trackContinueWatching,
                onChanged: widget.onToggleTrackContinueWatching,
              ),
              onTap: () => widget.onToggleTrackContinueWatching(
                !widget.trackContinueWatching,
              ),
              onLeft: _sections.navigation.returnToRail,
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget buildChannelPreviewPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.ondemand_video_rounded,
          title: 'Channel preview',
          meta:
              'Control whether the side panel tunes the focused channel '
              'while you browse.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            IptvTwoPaneRow(
              focusNode: _sections.navigation.paneNode(0),
              icon: Icons.play_circle_outline_rounded,
              title: 'Play channel previews',
              subtitle:
                  'Uses a provider stream while browsing. Turn it off to '
                  'save a connection; fullscreen playback still works',
              trailing: Switch(
                value: widget.channelPreviewEnabled,
                onChanged: widget.onToggleChannelPreview,
              ),
              onTap: () =>
                  widget.onToggleChannelPreview(!widget.channelPreviewEnabled),
              onLeft: _sections.navigation.returnToRail,
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget buildAppearancePane() {
    var row = 0;
    IconData styleIcon(String value) => switch (value) {
      'edition' => Icons.menu_book_rounded,
      'console' => Icons.tune_rounded,
      'spotlight' => Icons.calendar_view_week_rounded,
      _ => Icons.grid_view_rounded,
    };

    Widget styleRow({
      required IconData icon,
      required String value,
      required String title,
      required String subtitle,
      bool isLast = false,
    }) {
      return IptvTwoPaneRow(
        focusNode: _sections.navigation.paneNode(row++),
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Radio<String>(
          value: value,
          groupValue: widget.iptvStyle,
          onChanged: (v) =>
              v == null ? null : widget.onIptvStyleChanged?.call(v),
        ),
        onTap: () => widget.onIptvStyleChanged?.call(value),
        onLeft: _sections.navigation.returnToRail,
        isLast: isLast,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.style_rounded,
          title: 'Appearance',
          meta:
              'How the IPTV page looks on TV and desktop. Phones keep the '
              'classic list either way.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            for (var index = 0; index < kIptvStyleChoices.length; index++)
              styleRow(
                icon: styleIcon(kIptvStyleChoices[index].value),
                value: kIptvStyleChoices[index].value,
                title: kIptvStyleChoices[index].label,
                subtitle: kIptvStyleChoices[index].subtitle,
                isLast: index == kIptvStyleChoices.length - 1,
              ),
          ],
        ),
      ],
    );
  }

  Widget buildPlayerGuidePane() {
    var row = 0;
    Widget styleRow({
      required IconData icon,
      required String value,
      required String title,
      required String subtitle,
      bool isLast = false,
    }) {
      return IptvTwoPaneRow(
        focusNode: _sections.navigation.paneNode(row++),
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Radio<String>(
          value: value,
          groupValue: widget.playerGuideStyle,
          onChanged: (v) =>
              v == null ? null : widget.onPlayerGuideStyleChanged?.call(v),
        ),
        onTap: () => widget.onPlayerGuideStyleChanged?.call(value),
        onLeft: _sections.navigation.returnToRail,
        isLast: isLast,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.smart_display_rounded,
          title: 'Player guide',
          meta:
              'How the channel banner and in-player guide look during live '
              'TV — the next playback session uses the new look.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            styleRow(
              icon: Icons.play_circle_outline_rounded,
              value: 'classic',
              title: 'Classic',
              subtitle: "Today's look",
            ),
            styleRow(
              icon: Icons.blur_on_rounded,
              value: 'glass',
              title: 'Cinema Glass',
              subtitle:
                  'Translucent panels, one violet accent — modern streaming',
            ),
            styleRow(
              icon: Icons.menu_book_rounded,
              value: 'edition',
              title: 'Midnight Edition',
              subtitle: 'Ink panels and serif headlines — editorial',
            ),
            styleRow(
              icon: Icons.tune_rounded,
              value: 'console',
              title: 'Master Control',
              subtitle: 'Black instrument — mono numerals, amber machinery',
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget buildRecordingPane() {
    var row = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.fiber_manual_record_rounded,
          title: 'Recording',
          meta:
              'Background captures that survive zapping and leaving the '
              'app, plus programmes scheduled from the TV guide.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            if (widget.showEngineToggle)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.settings_backup_restore_rounded,
                title: 'Background recording engine',
                subtitle:
                    'Off returns to player-tied recording. Uses an '
                    'extra connection to your provider.',
                trailing: Switch(
                  value: widget.recordingEngineEnabled,
                  onChanged: widget.onToggleRecordingEngine,
                ),
                onTap: () => widget.onToggleRecordingEngine?.call(
                  !widget.recordingEngineEnabled,
                ),
                onLeft: _sections.navigation.returnToRail,
                isLast: !widget.recordingEngineEnabled,
              ),
            if (!widget.showEngineToggle || widget.recordingEngineEnabled)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.filter_none_rounded,
                title: 'Simultaneous recordings',
                subtitle:
                    '${widget.maxConcurrentRecordings} at a time — each is an '
                    'extra provider connection',
                trailing: _sections.panes.chevron,
                onTap: () => widget.onPickMaxConcurrent?.call(),
                onLeft: _sections.navigation.returnToRail,
                isLast: false,
              ),
            if ((!widget.showEngineToggle || widget.recordingEngineEnabled) &&
                widget.batteryExempt != null)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.battery_alert_rounded,
                title: 'Battery optimization',
                subtitle: widget.batteryExempt == true
                    ? 'Excluded — long recordings can run to the end'
                    : 'Optimized — the phone may kill long recordings; '
                          'tap to exclude Debrify',
                trailing: _sections.panes.chevron,
                onTap: () => widget.onRequestBatteryExemption?.call(),
                onLeft: _sections.navigation.returnToRail,
                isLast: false,
              ),
            if (!widget.showEngineToggle || widget.recordingEngineEnabled)
              IptvTwoPaneRow(
                focusNode: _sections.navigation.paneNode(row++),
                icon: Icons.event_rounded,
                title: 'Recordings',
                subtitle: widget.scheduledCount == 0
                    ? 'Live captures, schedules and your recorded files'
                    : '${widget.scheduledCount} scheduled · live captures '
                          'and recorded files',
                trailing: _sections.panes.chevron,
                onTap: () => widget.onOpenScheduledRecordings?.call(),
                onLeft: _sections.navigation.returnToRail,
                isLast: true,
              ),
          ],
        ),
      ],
    );
  }
}
