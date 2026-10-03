import 'dart:async';

import 'package:debrify/features/iptv/presentation/iptv_stage_chip.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_stage_info.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_rail_info.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_stage_floor.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';

typedef IptvPreviewLayoutDeps = ({
  IptvPlayerState playerState,
  IptvPreviewState previewState,
  IptvSettingsState settingsState,
  BuildContext Function() context,
  List<IptvListMeta> Function() customLists,
  bool Function() isTelevision,
  void Function(int ticket) markPreviewWinner,
  void Function(int ticket) onPreviewPlaybackFailed,
  Future<void> Function(IptvChannel channel, {bool Function()? shouldCancel})
  playChannel,
  Widget Function(Widget child) stageHoverGuard,
});

class IptvPreviewLayout {
  final IptvPreviewLayoutDeps _deps;
  final IptvPlayerState _playerState;
  final IptvPreviewState _previewState;
  final IptvSettingsState _settingsState;

  IptvPreviewLayout(this._deps)
    : _playerState = _deps.playerState,
      _previewState = _deps.previewState,
      _settingsState = _deps.settingsState;

  List<IptvListMeta> get _customLists => _deps.customLists();

  Widget buildPreviewRail({required bool touchSelector}) {
    final app = AppThemeScope.of(_deps.context());
    return _deps.stageHoverGuard(
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: _previewState.previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewState.previewShown,
            builder: (context, ch, _) {
              if (_deps.isTelevision()) {
                return buildTvFocusStage(ch, epoch);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildPreviewStage(ch, epoch),
                  const SizedBox(height: 16),
                  Expanded(child: IptvRailInfo(channel: ch)),
                  if (touchSelector) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('iptv-tablet-watch-fullscreen'),
                        onPressed: ch == null
                            ? null
                            : () => unawaited(_deps.playChannel(ch)),
                        style: FilledButton.styleFrom(
                          backgroundColor: app.seeAll.accent,
                          foregroundColor: app.inkOn(app.seeAll.accent),
                          disabledBackgroundColor: app.seeAll.panel2.withValues(
                            alpha: 0.72,
                          ),
                          disabledForegroundColor: app.core.tx.withValues(
                            alpha: 0.30,
                          ),
                          overlayColor: app.seeAll.accent2.withValues(
                            alpha: 0.18,
                          ),
                          shadowColor: app.seeAll.accent.withValues(
                            alpha: 0.34,
                          ),
                          elevation: 0,
                          side: BorderSide(
                            color: app.seeAll.accent2.withValues(alpha: 0.46),
                          ),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: app.shape.br(13),
                          ),
                        ),
                        icon: Icon(
                          ch?.contentType == 'series'
                              ? Icons.video_library_rounded
                              : Icons.fullscreen_rounded,
                          size: 21,
                        ),
                        label: Text(
                          ch?.contentType == 'series'
                              ? 'Open series'
                              : 'Watch fullscreen',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        _settingsState.channelPreviewEnabled
                            ? 'Scroll channels through the arrow to preview'
                            : 'Preview is off · choose Watch fullscreen',
                        style: TextStyle(
                          color: app.seeAll.accent2.withValues(alpha: 0.66),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _settingsState.channelPreviewEnabled
                            ? 'Hover a channel to preview  ·  Click to watch'
                            : 'Preview is off  ·  Click to watch',
                        style: TextStyle(
                          color: app.iptv.inkFaint,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Television's preview-first composition: a true 16:9 video surface in the
  /// upper section, with identity, EPG and key hints on a separate lower
  /// surface. Keeping chrome outside the video avoids cover-cropping a normal
  /// broadcast into a tall stage.
  Widget buildTvFocusStage(IptvChannel? ch, int epoch) {
    final app = AppThemeScope.of(_deps.context());
    return ClipRRect(
      borderRadius: app.shape.br(8),
      child: ColoredBox(
        color: app.iptv.stageBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildPreviewStage(ch, epoch),
            Expanded(
              child: ch == null
                  ? const SizedBox.shrink()
                  : IptvFocusStageInfo(
                      channel: ch,
                      hasLists: _customLists.isNotEmpty,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPreviewStage(IptvChannel? ch, int epoch) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Painted FIRST so the video covers it: the underlay engine's
            // punched hole wipes these pixels once frames arrive, and the
            // Texture engine simply draws over them. No Opacity/fade wrappers
            // here — anything layer-based over the punched hole would break
            // the punch-through (house underlay invariant). The floor's tuning
            // animation stops itself once frames show, so nothing keeps
            // repainting under a playing video.
            ValueListenableBuilder<bool>(
              valueListenable: _previewState.previewShowing,
              builder: (context, showing, _) => IptvStageFloor(
                channel: ch,
                tuning:
                    _settingsState.channelPreviewEnabled &&
                    ch != null &&
                    !showing,
              ),
            ),
            // Startup launch owns the screen: the stage's 900ms dwell would
            // otherwise open a SECOND live stream under the launching player.
            if (ch != null &&
                _settingsState.channelPreviewEnabled &&
                !_playerState.startupLaunchActive)
              ValueListenableBuilder<String?>(
                valueListenable: _previewState.previewStreamUrl,
                builder: (context, streamUrl, _) {
                  // Null while a Stremio channel resolves (or when every
                  // candidate died) — only the floor shows.
                  if (streamUrl == null) return const SizedBox.shrink();
                  // Ladder generation these callbacks belong to — they fire
                  // post-frame, possibly after focus moved to another channel.
                  final ticket = _previewState.previewResolveTicket;
                  return HeroTrailerBackdrop(
                    key: ValueKey('iptv-preview-$epoch'),
                    imageUrl: null,
                    videoUrl: streamUrl,
                    enabled: true,
                    live: true,
                    // The channel's declared UA/Referer — panels that guard
                    // playback with them guard the preview identically.
                    httpHeaders: ch.playbackHeaders,
                    imageBlurSigma: 0,
                    videoBlurSigma: 0,
                    // The dwell: arrowing down the guide never opens a stream
                    // until focus rests. Live streams also open slower than
                    // trailer clips, so a slightly longer debounce than Home's.
                    startDelay: const Duration(milliseconds: 900),
                    ambientVolume: 100,
                    onPlayingChanged: (p) {
                      if (ticket == _previewState.previewResolveTicket) {
                        _previewState.previewShowing.value = p;
                      }
                      if (p) _deps.markPreviewWinner(ticket);
                    },
                    onPlaybackFailed: () =>
                        _deps.onPreviewPlaybackFailed(ticket),
                    // Stremio ladder needs stalls to count as failures, or a
                    // silent-dead candidate would block the walk to the next.
                    firstFrameTimeout:
                        StremioIptvService.isStremioChannelUrl(ch.url)
                        ? const Duration(seconds: 12)
                        : null,
                  );
                },
              ),
            // Status chip — top-left, direct paint over the stage.
            Positioned(
              left: 10,
              top: 10,
              child: ValueListenableBuilder<bool>(
                valueListenable: _previewState.previewShowing,
                builder: (context, showing, _) => IptvStageChip(
                  channel: ch,
                  showing: showing,
                  previewEnabled: _settingsState.channelPreviewEnabled,
                ),
              ),
            ),
            // NO styled chrome over the video — final, device-verified rule.
            // Wrapping the preview froze the underlay; even full-rect
            // SIBLING overlays (Positioned.fill brackets/frame painted above
            // the hole, the status-chip pattern) made it flicker on real TV
            // hardware. The styles decorate the panel AROUND this stack only;
            // the shipped chip/identity are the sole overlays. Do not add
            // paint over the preview rect without an on-device test.
          ],
        ),
      ),
    );
  }
}
