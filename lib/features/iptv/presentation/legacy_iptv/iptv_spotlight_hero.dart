import 'dart:async';
import 'dart:io' show Platform;

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_programme_hero.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

typedef IptvSpotlightHeroDeps = ({
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvPreviewState previewState,
  IptvRecordingState recordingState,
  String? Function(IptvChannel channel) androidEngineTaskFor,
  Widget Function(IptvChannel? ch, int epoch) buildPreviewStage,
  bool Function(IptvChannel channel) channelEngineRecordable,
  List<IptvListMeta> Function() customLists,
  DateTime Function() Function() debugSpotlightNow,
  DesktopRecordingCapture? Function(IptvChannel channel) desktopCaptureFor,
  bool Function() isTelevision,
  void Function(IptvChannel channel) openSchedulePane,
  Future<void> Function(IptvChannel channel, EpgProgramme programme)
  playCatchup,
  Future<void> Function(IptvChannel channel, {bool Function()? shouldCancel})
  playChannel,
  void Function(EpgProgramme programme)? Function(IptvChannel channel)
  recordProgrammeActionFor,
  Future<void> Function(IptvChannel channel, {EpgProgramme? programme})
  showSpotlightChannelActions,
  Widget Function(VoidCallback action, Widget child) spotlightActivation,
  WidgetStateProperty<BorderSide?> Function() spotlightFocusBorder,
  Widget Function({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool selected,
  })
  spotlightIconAction,
  Widget Function(Widget child) stageHoverGuard,
  Future<void> Function(IptvChannel channel) stageRecordNow,
  Future<void> Function(IptvChannel channel, String taskId)
  stageStopAndroidRecording,
  Future<void> Function(DesktopRecordingCapture capture)
  stageStopDesktopRecording,
  Future<void> Function(IptvChannel channel, bool isFavorited) toggleFavorite,
});

class IptvSpotlightHero {
  final IptvSpotlightHeroDeps _deps;
  final IptvFocusState _focusState;
  final IptvMembershipState _membershipState;
  final IptvPreviewState _previewState;
  final IptvRecordingState _recordingState;

  IptvSpotlightHero(this._deps)
    : _focusState = _deps.focusState,
      _membershipState = _deps.membershipState,
      _previewState = _deps.previewState,
      _recordingState = _deps.recordingState;

  List<IptvListMeta> get _customLists => _deps.customLists();

  WidgetStateProperty<BorderSide?> get _spotlightFocusBorder =>
      _deps.spotlightFocusBorder();

  Widget buildSpotlightHero(IptvSpotlightLayoutMode mode) {
    return _deps.stageHoverGuard(
      ValueListenableBuilder<int>(
        valueListenable: _previewState.previewEpoch,
        builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
          valueListenable: _previewState.previewShown,
          builder: (context, channel, _) =>
              ValueListenableBuilder<EpgProgramme?>(
                valueListenable: _previewState.spotlightProgrammeShown,
                builder: (context, programme, _) => SpotlightProgrammeHero(
                  now: _deps.debugSpotlightNow(),
                  channel: channel,
                  selectedProgramme: programme,
                  // TV uses short/held OK on the guide row for these actions.
                  actionsBuilder: _deps.isTelevision()
                      ? null
                      : (context, activeProgramme, dense) =>
                            buildSpotlightHeroActions(
                              channel,
                              programme: activeProgramme,
                              compact:
                                  mode == IptvSpotlightLayoutMode.compact ||
                                  dense,
                            ),
                  // Keep the established preview subtree byte-for-byte.
                  // Spotlight only lays it out beside programme information.
                  previewSlot: Semantics(
                    button: channel != null,
                    label: channel == null
                        ? 'Channel preview'
                        : 'Watch ${channel.name}',
                    child: GestureDetector(
                      key: const ValueKey('spotlight-preview-play'),
                      behavior: HitTestBehavior.opaque,
                      onTap: channel == null
                          ? null
                          : () => unawaited(_deps.playChannel(channel)),
                      child: _deps.buildPreviewStage(channel, epoch),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget buildSpotlightHeroActions(
    IptvChannel? channel, {
    required EpgProgramme? programme,
    required bool compact,
  }) {
    if (channel == null) return const SizedBox.shrink();
    final t = IptvStyleTokens.spotlight;
    final primary = spotlightPrimaryAction(channel, programme);
    final rawRecord = spotlightRecordAction(channel);
    final record =
        programme == null ||
            programme.airsAt(DateTime.now()) ||
            rawRecord?.label == 'Stop'
        ? rawRecord
        : null;
    final isFavorited = _membershipState.favoriteUrls.contains(channel.url);
    final canSave = channel.contentType != 'series';
    final hasMore =
        record != null || canSave || IptvEpgService.isEpgCapable(channel);

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _deps.spotlightActivation(
            primary.action,
            FilledButton.icon(
              focusNode: _focusState.spotlightPrimaryFocusNode,
              onPressed: primary.action,
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: t.focusInk,
                backgroundColor: t.focusFill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ).copyWith(side: _spotlightFocusBorder),
              icon: Icon(primary.icon, size: 19),
              label: Text(primary.label),
            ),
          ),
          if (hasMore) ...[
            const SizedBox(width: 5),
            _deps.spotlightIconAction(
              tooltip: 'More channel actions',
              icon: Icons.more_horiz_rounded,
              onPressed: () => _deps.showSpotlightChannelActions(
                channel,
                programme: programme,
              ),
            ),
          ],
        ],
      );
    }

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final compactPadding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 8,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _deps.spotlightActivation(
          primary.action,
          FilledButton.icon(
            focusNode: _focusState.spotlightPrimaryFocusNode,
            style: FilledButton.styleFrom(
              backgroundColor: t.focusFill,
              foregroundColor: t.focusInk,
              padding: compactPadding,
              visualDensity: VisualDensity.compact,
              shape: buttonShape,
            ).copyWith(side: _spotlightFocusBorder),
            onPressed: primary.action,
            icon: Icon(primary.icon, size: 18),
            label: Text(primary.label),
          ),
        ),
        if (record != null)
          _deps.spotlightActivation(
            record.action,
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: record.label == 'Stop' ? t.rec : t.fg,
                side: BorderSide(
                  color: record.label == 'Stop' ? t.rec : t.hairline2,
                ),
                padding: compactPadding,
                visualDensity: VisualDensity.compact,
                shape: buttonShape,
              ),
              onPressed: record.action,
              icon: Icon(record.icon, size: 16),
              label: Text(record.label),
            ),
          ),
        if (canSave)
          _deps.spotlightIconAction(
            tooltip: isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
            icon: isFavorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            selected: isFavorited,
            onPressed: () =>
                unawaited(_deps.toggleFavorite(channel, !isFavorited)),
          ),
        if ((canSave && _customLists.isNotEmpty) ||
            IptvEpgService.isEpgCapable(channel))
          _deps.spotlightIconAction(
            tooltip: 'More channel actions',
            icon: Icons.more_horiz_rounded,
            onPressed: () => _deps.showSpotlightChannelActions(
              channel,
              programme: programme,
            ),
          ),
      ],
    );
  }

  ({String label, IconData icon, VoidCallback action}) spotlightPrimaryAction(
    IptvChannel channel,
    EpgProgramme? programme,
  ) {
    if (channel.contentType == 'series') {
      return (
        label: 'Open',
        icon: Icons.open_in_new_rounded,
        action: () => unawaited(_deps.playChannel(channel)),
      );
    }
    if (programme != null) {
      final now = DateTime.now();
      if (programme.airsAt(now)) {
        return (
          label: 'Watch',
          icon: Icons.play_arrow_rounded,
          action: () => unawaited(_deps.playChannel(channel)),
        );
      }
      if (IptvEpgService.isCatchupAvailable(channel, programme)) {
        return (
          label: 'Replay',
          icon: Icons.replay_rounded,
          action: () => unawaited(_deps.playCatchup(channel, programme)),
        );
      }
      if (programme.start.isAfter(now)) {
        final recordProgramme = _deps.recordProgrammeActionFor(channel);
        if (recordProgramme != null) {
          return (
            label: 'Record',
            icon: Icons.fiber_manual_record_rounded,
            action: () => recordProgramme(programme),
          );
        }
      }
      return (
        label: 'Guide',
        icon: Icons.calendar_month_rounded,
        action: () => _deps.openSchedulePane(channel),
      );
    }
    return (
      label: 'Watch',
      icon: Icons.play_arrow_rounded,
      action: () => unawaited(_deps.playChannel(channel)),
    );
  }

  ({String label, IconData icon, VoidCallback action})? spotlightRecordAction(
    IptvChannel channel,
  ) {
    final desktopCapture = _deps.desktopCaptureFor(channel);
    if (desktopCapture != null) {
      return (
        label: 'Stop',
        icon: Icons.stop_rounded,
        action: () =>
            unawaited(_deps.stageStopDesktopRecording(desktopCapture)),
      );
    }
    final androidTask = !kIsWeb && Platform.isAndroid
        ? _deps.androidEngineTaskFor(channel)
        : null;
    if (androidTask != null) {
      return (
        label: 'Stop',
        icon: Icons.stop_rounded,
        action: () =>
            unawaited(_deps.stageStopAndroidRecording(channel, androidTask)),
      );
    }
    if (_recordingState.pageCanRecord &&
        _deps.channelEngineRecordable(channel)) {
      return (
        label: 'Record',
        icon: Icons.fiber_manual_record_rounded,
        action: () => unawaited(_deps.stageRecordNow(channel)),
      );
    }
    return null;
  }
}
