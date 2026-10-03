import 'dart:async';
import 'dart:io' show Platform;

import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/iptv_command_rail.dart';
import 'package:debrify/widgets/iptv/iptv_epg_panel.dart';
import 'package:debrify/widgets/iptv/styles/iptv_console_widgets.dart';
import 'package:debrify/widgets/iptv/styles/iptv_edition_hero.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

typedef IptvTwoPaneLayoutDeps = ({
  IptvCatalogState catalogState,
  IptvMembershipState membershipState,
  IptvPreviewState previewState,
  IptvRecordingState recordingState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  IptvStatusState statusState,
  Widget Function() buildCockpitStage,
  Widget Function({bool tvPane, bool touchSelector, bool cockpit}) buildContent,
  Widget Function({required bool touchSelector}) buildPreviewRail,
  Widget Function() buildQuietFilters,
  void Function() closeSchedulePane,
  bool Function() isTelevision,
  void Function() navigateToManageSources,
  void Function(IptvPlaylist? playlist, {bool focusContent}) onPlaylistChanged,
  void Function() openScheduledRecordings,
  Future<void> Function(IptvChannel channel, EpgProgramme programme)
  playCatchup,
  void Function(EpgProgramme programme)? Function(IptvChannel channel)
  recordProgrammeActionFor,
  Future<void> Function() refreshAndroidRecordingState,
});

// ── TV two-pane ──────────────────────────────────────────────────────────
class IptvTwoPaneLayout {
  final IptvTwoPaneLayoutDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvMembershipState _membershipState;
  final IptvPreviewState _previewState;
  final IptvRecordingState _recordingState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;
  final IptvStatusState _statusState;

  IptvTwoPaneLayout(this._deps)
    : _catalogState = _deps.catalogState,
      _membershipState = _deps.membershipState,
      _previewState = _deps.previewState,
      _recordingState = _deps.recordingState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState,
      _statusState = _deps.statusState;

  Widget buildTvTwoPane(BoxConstraints c, {required bool touchSelector}) {
    // Every source (Favorites, Continue watching, and each playlist) lives in
    // the header's Sources dropdown now — no left rail eating horizontal space.
    // TV uses a wider focus stage; desktop keeps the compact preview rail so a
    // resizable window never gives up too much guide space.
    final paneW = c.maxWidth;
    final scheduleChannel = _selectionState.scheduleChannel;

    // An open schedule covers the guide column in place — the preview
    // keeps playing, and BACK restores the list exactly as it was. Offstage
    // (not a swap) keeps the grid, its scroll offset and its focus nodes
    // alive, so closing can hand focus straight back to the originating row;
    // ExcludeFocus keeps DPAD from wandering into the hidden rows meanwhile.
    Widget guideStack({required bool cockpit}) => Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: scheduleChannel != null,
          child: ExcludeFocus(
            excluding: scheduleChannel != null,
            // The LayoutBuilder is inside the Stack (bounded), so the styled
            // branches can gate their display inserts on the real guide
            // height. The command branch below it is the shipped tree,
            // untouched.
            child: LayoutBuilder(
              builder: (context, gc) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 24, 4),
                    child: _deps.buildQuietFilters(),
                  ),
                  // First Edition's editorial hero — display-only (no focus
                  // nodes), inside the Offstage subtree so the schedule pane
                  // covers it. Gate = every vertical consumer at worst case:
                  // filter line ~50 + hero 128 + progressive-status line ~24
                  // + grid top pad 8 + 4 tall EPG rows (4x118) + 3 gaps
                  // (3x4) = 694 → 700 with margin, so >=4 full rows always
                  // survive the insert.
                  if (cockpit &&
                      _settingsState.iptvStyle == IptvStyle.edition &&
                      gc.maxHeight >= 700)
                    IptvEditionHero(
                      channel: _previewState.previewShown,
                      tokens: IptvStyleTokens.edition,
                      suspended: scheduleChannel != null,
                    ),
                  // Master Control's 6-hour strip — same display-only rules
                  // as the hero. Same budget with its own 96px height:
                  // 50 + 96 + 24 + 8 + 472 + 12 = 662 → 670 with margin.
                  if (cockpit &&
                      _settingsState.iptvStyle == IptvStyle.console &&
                      gc.maxHeight >= 670)
                    IptvConsoleTimeline(
                      channel: _previewState.previewShown,
                      tokens: IptvStyleTokens.console,
                      suspended: scheduleChannel != null,
                    ),
                  Expanded(
                    child: _deps.buildContent(
                      tvPane: true,
                      touchSelector: touchSelector,
                      cockpit: cockpit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (scheduleChannel != null)
          IptvSchedulePane(
            channel: scheduleChannel,
            onClose: _deps.closeSchedulePane,
            isTelevision: _deps.isTelevision(),
            onPlayProgramme: (programme) =>
                _deps.playCatchup(scheduleChannel, programme),
            // The full-day guide records too — same gates and confirm flow
            // as the stage's compact list (it was the one schedule surface
            // that never got the callback).
            onRecordProgramme: _deps.recordProgrammeActionFor(scheduleChannel),
          ),
      ],
    );

    if (!touchSelector) {
      // Command Center (TV + desktop pointer): rail → guide → stage cockpit.
      // Geometry does the DPAD work — the rail's focusables sit left of the
      // grid, the stage's actions sit right of it, and LEFT from the rail
      // bubbles to the shell's global action (the app sidebar) untouched.
      final railW = paneW >= 1150 ? 196.0 : 172.0;
      final cockpitStageW = (paneW * (paneW >= 1200 ? 0.34 : 0.36)).clamp(
        300.0,
        480.0,
      );
      final cockpitTokens = IptvStyleTokens.of(_settingsState.iptvStyle);
      final cockpitRow = Row(
        key: const ValueKey('iptv-cockpit'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railW,
            child: IptvCommandRail(
              tokens: cockpitTokens,
              playlists: _settingsState.playlists,
              selectedPlaylist: _settingsState.selectedPlaylist,
              customLists: _membershipState.lists,
              sourceCounts: _recordingState.sourceCounts,
              favoritesCount: _membershipState.favoriteUrls.length,
              scheduledCount: _recordingState.scheduledCount,
              // focusContent: OK is a decision, so it lands DPAD on the
              // channels it just loaded. (Merely walking RIGHT does not
              // select — it traverses into the guide, which still shows the
              // selected source.)
              onSelectPlaylist: (p) =>
                  _deps.onPlaylistChanged(p, focusContent: true),
              onOpenScheduled: _deps.openScheduledRecordings,
              onManageSources: _deps.navigateToManageSources,
              // Engine off / unsupported: don't advertise a scheduler that
              // would refuse to work (settings hides its row in this state).
              showScheduled: _recordingState.pageCanRecord,
            ),
          ),
          Expanded(
            // Styled looks paint the guide column's background HERE, not as
            // one sheet under the whole cockpit: the stage's RepaintBoundary
            // is its own compositing layer, so the preview's BlendMode.clear
            // hole cannot erase paint living in an ancestor layer — a page-
            // wide ColoredBox turns the live underlay video into an opaque
            // block (frozen frame + audio-only on TV). The rail and status
            // bar paint their own; the stage's panel color already lives
            // INSIDE the boundary where the hole clears it.
            child: cockpitTokens == null
                ? guideStack(cockpit: true)
                : ColoredBox(
                    color: cockpitTokens.bg,
                    child: guideStack(cockpit: true),
                  ),
          ),
          SizedBox(width: cockpitStageW, child: _deps.buildCockpitStage()),
        ],
      );
      // NO ColoredBox around the cockpit row — see the guide-column note
      // above (the underlay hole must composite against transparency all the
      // way down). Master Control adds its status strip above the cockpit —
      // the Row stays bounded inside the Expanded.
      if (cockpitTokens == null) return cockpitRow;
      if (_settingsState.iptvStyle == IptvStyle.console) {
        return Column(
          children: [
            IptvConsoleStatusBar(
              tokens: cockpitTokens,
              sourceName: _settingsState.selectedPlaylist?.name ?? 'IPTV',
              channelCount: _catalogState.filteredChannels.length,
              recCount: (!kIsWeb && Platform.isAndroid)
                  ? _recordingState.androidRecordingsByUrl.length
                  : DesktopRecordingService.instance.isSupported
                  ? DesktopRecordingService.instance.captures.length
                  : 0,
              schedCount: _recordingState.scheduledCount,
              statusText: _statusState.chipState == CatalogChipState.hidden
                  ? null
                  : _statusState.chipMessage,
              // The Android url→task map refreshes on selected events only;
              // the bar's tick reconciles it so REC can't sit stale while
              // focus is parked (no-op off Android / when recording is off).
              onTick: () => unawaited(_deps.refreshAndroidRecordingState()),
            ),
            Expanded(child: cockpitRow),
          ],
        );
      }
      return cockpitRow;
    }

    // Touch tablet keeps the shipped preview-left arrangement unchanged.
    final stageW = (paneW * 0.40).clamp(320.0, 470.0);
    return Row(
      key: const ValueKey('iptv-tablet-two-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: stageW,
          child: _deps.buildPreviewRail(touchSelector: touchSelector),
        ),
        Expanded(child: guideStack(cockpit: false)),
      ],
    );
  }
}
