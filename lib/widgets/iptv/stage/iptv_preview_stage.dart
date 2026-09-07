import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/stremio_iptv_service.dart';
import '../../hero_trailer_backdrop.dart';
import 'iptv_stage_chip.dart';
import 'iptv_stage_floor.dart';
import 'iptv_stage_state.dart';

/// Lets a preview stage claim the pointer, so nothing repoints it while the
/// cursor is inside on its way to Watch or Record. A row the pointer RESTS on
/// is exempt (see the results view's channel-focus handler) — the cursor
/// cannot be on a row and in the stage at once, so that exemption also means a
/// flag left stuck true by a missed onExit can never strand the hover preview.
Widget iptvStageHoverGuard({
  required bool isTelevision,
  required ValueChanged<bool> onPointerInStage,
  required Widget child,
}) {
  if (isTelevision) return child;
  return MouseRegion(
    onEnter: (_) => onPointerInStage(true),
    onExit: (_) => onPointerInStage(false),
    child: child,
  );
}

/// The 16:9 video surface every IPTV stage is built on: the static floor, the
/// embedded live preview when one is armed, and the LIVE/TUNING status chip.
/// Shared by the Command Center cockpit and the touch tablet's preview rail.
class IptvPreviewStage extends StatelessWidget {
  const IptvPreviewStage({
    super.key,
    required this.channel,
    required this.epoch,
    required this.stage,
  });

  /// The channel to show; null renders the floor's empty placeholder.
  final IptvChannel? channel;

  /// The preview generation — keys the backdrop, so a bump remounts it.
  final int epoch;

  final IptvStageState stage;

  @override
  Widget build(BuildContext context) {
    final ch = channel;
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
              valueListenable: stage.showing,
              builder: (context, showing, _) => IptvStageFloor(
                channel: ch,
                tuning: stage.previewEnabled() && ch != null && !showing,
              ),
            ),
            // Startup launch owns the screen: the stage's 900ms dwell would
            // otherwise open a SECOND live stream under the launching player.
            if (ch != null &&
                stage.previewEnabled() &&
                !stage.startupLaunchActive())
              ValueListenableBuilder<String?>(
                valueListenable: stage.streamUrl,
                builder: (context, streamUrl, _) {
                  // Null while a Stremio channel resolves (or when every
                  // candidate died) — only the floor shows.
                  if (streamUrl == null) return const SizedBox.shrink();
                  // Ladder generation these callbacks belong to — they fire
                  // post-frame, possibly after focus moved to another channel.
                  final ticket = stage.resolveTicket();
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
                      if (ticket == stage.resolveTicket()) {
                        stage.showing.value = p;
                      }
                      if (p) stage.onMarkWinner(ticket);
                    },
                    onPlaybackFailed: () => stage.onPlaybackFailed(ticket),
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
                valueListenable: stage.showing,
                builder: (context, showing, _) => IptvStageChip(
                  channel: ch,
                  showing: showing,
                  previewEnabled: stage.previewEnabled(),
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
