import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/iptv/application/iptv_rail_resolution.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/browse/brand_accent.dart';
import 'package:debrify/widgets/iptv/iptv_epg_panel.dart';
import 'package:debrify/widgets/iptv/iptv_stage_panel.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

typedef IptvCockpitStageDeps = ({
  IptvMembershipState membershipState,
  IptvPreviewState previewState,
  IptvRecordingState recordingState,
  IptvSettingsState settingsState,
  String? Function(IptvChannel channel) androidEngineTaskFor,
  Widget Function(IptvChannel? ch, int epoch) buildPreviewStage,
  bool Function(IptvChannel channel) channelEngineRecordable,
  BuildContext Function() context,
  DesktopRecordingCapture? Function(IptvChannel channel) desktopCaptureFor,
  bool Function() isTelevision,
  void Function(IptvChannel channel) openSchedulePane,
  Future<void> Function(IptvChannel channel, EpgProgramme programme)
  playCatchup,
  Future<void> Function(IptvChannel channel, {bool Function()? shouldCancel})
  playChannel,
  void Function() returnFocusFromStage,
  Future<String?> Function(IptvChannel channel, EpgProgramme programme)
  scheduleProgrammeFromStage,
  Widget Function(Widget child) stageHoverGuard,
  Future<void> Function(IptvChannel channel) stageRecordNow,
  Future<void> Function(IptvChannel channel, String taskId)
  stageStopAndroidRecording,
  Future<void> Function(DesktopRecordingCapture capture)
  stageStopDesktopRecording,
  Future<void> Function(IptvChannel channel, bool isFavorited) toggleFavorite,
});

// ---- Command Center (rail + stage cockpit) ------------------------------
class IptvCockpitStage {
  final IptvCockpitStageDeps _deps;
  final IptvMembershipState _membershipState;
  final IptvPreviewState _previewState;
  final IptvRecordingState _recordingState;
  final IptvSettingsState _settingsState;

  IptvCockpitStage(this._deps)
    : _membershipState = _deps.membershipState,
      _previewState = _deps.previewState,
      _recordingState = _deps.recordingState,
      _settingsState = _deps.settingsState;

  /// The Command Center stage: live preview on top, identity + now/next,
  /// then the action row and the focused channel's compact day schedule
  /// (IptvStagePanel). One RepaintBoundary so the preview's frames never
  /// re-rasterize the panel and vice versa.
  Widget buildCockpitStage() {
    final app = AppThemeScope.of(_deps.context());
    return _deps.stageHoverGuard(
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 14, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: _previewState.previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewState.previewShown,
            builder: (context, ch, _) {
              return RepaintBoundary(
                child: ClipRRect(
                  borderRadius: app.shape.br(10),
                  child: ColoredBox(
                    color:
                        IptvStyleTokens.of(_settingsState.iptvStyle)?.panel ??
                        app.iptv.stageBg,
                    child: ch == null
                        ? const SizedBox.expand()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // UNDERLAY RULE (device-verified 2026-08-05):
                              // the preview subtree is handed over UNWRAPPED,
                              // byte-identical to the shipped Command Center
                              // path. Wrapping it (a CustomPaint, a Column, a
                              // foregroundDecoration Container) froze the
                              // underlay video on Android TV — frozen frame +
                              // audio-only. Styled chrome therefore lives as
                              // SIBLINGS: the caption below is a plain child
                              // of this ALREADY-EXISTING Column, and the
                              // brackets/frame paint inside the preview's own
                              // Stack next to the status chip.
                              _deps.buildPreviewStage(ch, epoch),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: cockpitIdentity(ch),
                              ),
                              Expanded(
                                // Rebuilds when an XMLTV guide finishes loading
                                // (contextVersion), so a channel that probed
                                // "no EPG" a moment ago gets its schedule.
                                child: ValueListenableBuilder<int>(
                                  valueListenable:
                                      IptvEpgService.instance.contextVersion,
                                  builder: (context, epgVersion, _) {
                                    final desktopCapture = _deps
                                        .desktopCaptureFor(ch);
                                    final androidTask =
                                        (!kIsWeb && Platform.isAndroid)
                                        ? _deps.androidEngineTaskFor(ch)
                                        : null;
                                    return IptvStagePanel(
                                      key: ValueKey('stage-${ch.url}'),
                                      tokens: IptvStyleTokens.of(
                                        _settingsState.iptvStyle,
                                      ),
                                      channel: ch,
                                      isTelevision: _deps.isTelevision(),
                                      isFavorited: _membershipState.favoriteUrls
                                          .contains(ch.url),
                                      canRecord: _recordingState.pageCanRecord,
                                      isRecordingThis:
                                          desktopCapture != null ||
                                          androidTask != null,
                                      epgContextVersion: epgVersion,
                                      onWatch: () =>
                                          unawaited(_deps.playChannel(ch)),
                                      onExitLeft: _deps.returnFocusFromStage,
                                      onRecordNow: desktopCapture != null
                                          ? () => unawaited(
                                              _deps.stageStopDesktopRecording(
                                                desktopCapture,
                                              ),
                                            )
                                          : androidTask != null
                                          ? () => unawaited(
                                              _deps.stageStopAndroidRecording(
                                                ch,
                                                androidTask,
                                              ),
                                            )
                                          : _deps.channelEngineRecordable(ch)
                                          ? () => unawaited(
                                              _deps.stageRecordNow(ch),
                                            )
                                          : null,
                                      // _toggleFavorite takes the DESIRED state
                                      // (the row passes !isFavorited too) —
                                      // passing the current one would write a
                                      // no-op.
                                      onToggleFavorite:
                                          ch.contentType == 'series'
                                          ? null
                                          : () => unawaited(
                                              _deps.toggleFavorite(
                                                ch,
                                                !_membershipState.favoriteUrls
                                                    .contains(ch.url),
                                              ),
                                            ),
                                      // Only when a guide can exist — otherwise
                                      // the pane could only say "No guide data".
                                      onOpenFullSchedule:
                                          IptvEpgService.isEpgCapable(ch)
                                          ? () => _deps.openSchedulePane(ch)
                                          : null,
                                      // Stricter than Record-now: scheduling has
                                      // no player probe at alarm time, so REC
                                      // rows only appear on affirmatively-TS/
                                      // Xtream channels — never a tag that gets
                                      // refused on press.
                                      onScheduleProgramme:
                                          LiveRecordingService.isSchedulableUrl(
                                            ch.url,
                                          )
                                          ? _deps.scheduleProgrammeFromStage
                                          : null,
                                      onPlayProgramme: (c, p) =>
                                          unawaited(_deps.playCatchup(c, p)),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Compact identity header for the cockpit: logo chip, CH number + name,
  /// group/resolution sub-line, then the shared now/next EPG card.
  Widget cockpitIdentity(IptvChannel channel) {
    final app = AppThemeScope.of(_deps.context());
    final t = IptvStyleTokens.of(_settingsState.iptvStyle);
    final isConsole = _settingsState.iptvStyle == IptvStyle.console;
    // Styled looks never paint the brand color.
    final brand = t == null ? brandAccentFor(channel.name) : Colors.transparent;
    final resMatch = railResExp.firstMatch(channel.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? channel.name
        : channel.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final group = channel.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: t == null
                  ? BoxDecoration(
                      borderRadius: app.shape.br(8),
                      border: Border.all(color: app.iptv.hairline),
                      color: Color.alphaBlend(
                        brand.withValues(alpha: 0.18),
                        const Color(0xFF171B19),
                      ),
                    )
                  : BoxDecoration(
                      shape: isConsole ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isConsole ? app.shape.br(6) : null,
                      border: Border.all(color: t.hairline2),
                      color: t.fg.withValues(alpha: 0.03),
                    ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: channel.logoUrl!,
                        cacheManager: DebrifyImageCache.iptvLogos,
                        fit: BoxFit.contain,
                        memCacheHeight: 96,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.live_tv_rounded,
                          size: 16,
                          color: t?.fgDim ?? brand.withValues(alpha: 0.85),
                        ),
                      )
                    : Icon(
                        Icons.live_tv_rounded,
                        size: 16,
                        color: t?.fgDim ?? brand.withValues(alpha: 0.85),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.channelNumber == null
                        ? displayName
                        : 'CH ${channel.channelNumber}  $displayName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t == null
                        ? TextStyle(
                            color: app.core.tx,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          )
                        : TextStyle(
                            color: t.fg,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                            fontFamily: t.nameFamily.isEmpty
                                ? null
                                : t.nameFamily,
                          ),
                  ),
                  if (subParts.isNotEmpty)
                    Text(
                      subParts.join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t == null
                          ? TextStyle(
                              color: app.core.tx.withValues(alpha: 0.5),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            )
                          : TextStyle(
                              color: t.fgDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              fontFamily: t.monoFamily.isEmpty
                                  ? null
                                  : t.monoFamily,
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        IptvRailEpgCard(
          channel: channel,
          stageOverlay: true,
          dense: true,
          tokens: t,
        ),
      ],
    );
  }
}
