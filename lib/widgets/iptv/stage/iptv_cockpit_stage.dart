import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/debrify_image_cache.dart';
import '../../../services/desktop_recording_service.dart';
import '../../../services/iptv_epg_service.dart';
import '../../../services/live_recording_service.dart';
import '../../../theme/app_theme_scope.dart';
import '../../browse/brand_accent.dart';
import '../iptv_epg_panel.dart';
import '../iptv_stage_panel.dart';
import '../styles/iptv_style.dart';
import 'iptv_preview_stage.dart';
import 'iptv_rail_info.dart';
import 'iptv_stage_state.dart';

/// The Command Center stage: live preview on top, identity + now/next,
/// then the action row and the focused channel's compact day schedule
/// (IptvStagePanel). One RepaintBoundary so the preview's frames never
/// re-rasterize the panel and vice versa.
class IptvCockpitStage extends StatelessWidget {
  const IptvCockpitStage({
    super.key,
    required this.stage,
    required this.style,
    required this.isTelevision,
    required this.onPointerInStage,
    required this.favoriteUrls,
    required this.canRecord,
    required this.desktopCaptureFor,
    required this.androidEngineTaskFor,
    required this.channelEngineRecordable,
    required this.onWatch,
    required this.onExitLeft,
    required this.onStopDesktopRecording,
    required this.onStopAndroidRecording,
    required this.onRecordNow,
    required this.onToggleFavorite,
    required this.onOpenFullSchedule,
    required this.onScheduleProgramme,
    required this.onPlayProgramme,
  });

  final IptvStageState stage;

  /// The page's styled look; drives the panel/identity tokens.
  final IptvStyle style;

  final bool isTelevision;

  /// The pointer entered (true) or left (false) the stage — the page uses it
  /// to stop repointing the preview while the cursor is on its way to an
  /// action. See [iptvStageHoverGuard].
  final ValueChanged<bool> onPointerInStage;

  /// Live view of the page's favourites; read at build time.
  final Set<String> favoriteUrls;

  /// Recording availability for the whole page (engine on Android 10+,
  /// desktop capture elsewhere) — false hides Record + REC rows.
  final bool canRecord;

  /// The desktop capture running for this channel, if any.
  final DesktopRecordingCapture? Function(IptvChannel channel)
  desktopCaptureFor;

  /// The Android engine task recording this channel, if any.
  final String? Function(IptvChannel channel) androidEngineTaskFor;

  /// Whether the engine could start a recording for this channel at all.
  final bool Function(IptvChannel channel) channelEngineRecordable;

  final ValueChanged<IptvChannel> onWatch;
  final VoidCallback onExitLeft;
  final ValueChanged<DesktopRecordingCapture> onStopDesktopRecording;
  final void Function(IptvChannel channel, String task) onStopAndroidRecording;
  final ValueChanged<IptvChannel> onRecordNow;

  /// Takes the DESIRED state, not the current one.
  final void Function(IptvChannel channel, bool isFavorited) onToggleFavorite;

  final ValueChanged<IptvChannel> onOpenFullSchedule;
  final Future<String?> Function(IptvChannel channel, EpgProgramme programme)
  onScheduleProgramme;
  final void Function(IptvChannel channel, EpgProgramme programme)
  onPlayProgramme;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return iptvStageHoverGuard(
      isTelevision: isTelevision,
      onPointerInStage: onPointerInStage,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 14, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: stage.epoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: stage.shown,
            builder: (context, ch, _) {
              return RepaintBoundary(
                child: ClipRRect(
                  borderRadius: app.shape.br(10),
                  child: ColoredBox(
                    color: IptvStyleTokens.of(style)?.panel ?? app.iptv.stageBg,
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
                              IptvPreviewStage(
                                channel: ch,
                                epoch: epoch,
                                stage: stage,
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: IptvCockpitIdentity(
                                  channel: ch,
                                  style: style,
                                ),
                              ),
                              Expanded(
                                // Rebuilds when an XMLTV guide finishes loading
                                // (contextVersion), so a channel that probed
                                // "no EPG" a moment ago gets its schedule.
                                child: ValueListenableBuilder<int>(
                                  valueListenable:
                                      IptvEpgService.instance.contextVersion,
                                  builder: (context, epgVersion, _) {
                                    final desktopCapture = desktopCaptureFor(
                                      ch,
                                    );
                                    final androidTask =
                                        (!kIsWeb && Platform.isAndroid)
                                        ? androidEngineTaskFor(ch)
                                        : null;
                                    return IptvStagePanel(
                                      key: ValueKey('stage-${ch.url}'),
                                      tokens: IptvStyleTokens.of(style),
                                      channel: ch,
                                      isTelevision: isTelevision,
                                      isFavorited: favoriteUrls.contains(
                                        ch.url,
                                      ),
                                      canRecord: canRecord,
                                      isRecordingThis:
                                          desktopCapture != null ||
                                          androidTask != null,
                                      epgContextVersion: epgVersion,
                                      onWatch: () => onWatch(ch),
                                      onExitLeft: onExitLeft,
                                      onRecordNow: desktopCapture != null
                                          ? () => onStopDesktopRecording(
                                              desktopCapture,
                                            )
                                          : androidTask != null
                                          ? () => onStopAndroidRecording(
                                              ch,
                                              androidTask,
                                            )
                                          : channelEngineRecordable(ch)
                                          ? () => onRecordNow(ch)
                                          : null,
                                      // onToggleFavorite takes the DESIRED
                                      // state (the row passes !isFavorited
                                      // too) — passing the current one would
                                      // write a no-op.
                                      onToggleFavorite:
                                          ch.contentType == 'series'
                                          ? null
                                          : () => onToggleFavorite(
                                              ch,
                                              !favoriteUrls.contains(ch.url),
                                            ),
                                      // Only when a guide can exist — otherwise
                                      // the pane could only say "No guide data".
                                      onOpenFullSchedule:
                                          IptvEpgService.isEpgCapable(ch)
                                          ? () => onOpenFullSchedule(ch)
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
                                          ? onScheduleProgramme
                                          : null,
                                      onPlayProgramme: (c, p) =>
                                          onPlayProgramme(c, p),
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
}

/// Compact identity header for the cockpit: logo chip, CH number + name,
/// group/resolution sub-line, then the shared now/next EPG card.
class IptvCockpitIdentity extends StatelessWidget {
  const IptvCockpitIdentity({
    super.key,
    required this.channel,
    required this.style,
  });

  final IptvChannel channel;
  final IptvStyle style;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = IptvStyleTokens.of(style);
    final isConsole = style == IptvStyle.console;
    // Styled looks never paint the brand color.
    final brand = t == null ? brandAccentFor(channel.name) : Colors.transparent;
    final resMatch = iptvRailResolutionExp.firstMatch(channel.name);
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
