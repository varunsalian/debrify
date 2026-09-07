import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../theme/app_theme_scope.dart';
import 'iptv_preview_stage.dart';
import 'iptv_rail_info.dart';
import 'iptv_stage_state.dart';

/// The preview-left arrangement: the 16:9 stage on top, the identity/EPG block
/// under it, and — on a touch tablet — a full-width fullscreen launcher plus
/// the hint line that tells the user how the stage gets its channel.
class IptvPreviewRail extends StatelessWidget {
  const IptvPreviewRail({
    super.key,
    required this.stage,
    required this.isTelevision,
    required this.touchSelector,
    required this.onPointerInStage,
    required this.onWatch,
    required this.tvFocusStageBuilder,
  });

  final IptvStageState stage;
  final bool isTelevision;

  /// The tablet's scroll-through-a-fixed-arrow selector, which replaces the
  /// pointer's hover-to-preview grammar and adds the launch button.
  final bool touchSelector;

  /// See [iptvStageHoverGuard].
  final ValueChanged<bool> onPointerInStage;

  final ValueChanged<IptvChannel> onWatch;

  /// Television's preview-first composition. Still supplied by the page,
  /// because it renders a private focus-info block that lives there; the rail
  /// itself has never been reachable with [isTelevision] true (the touch
  /// tablet layout that hosts it requires a non-TV touch platform).
  final Widget Function(IptvChannel? channel, int epoch) tvFocusStageBuilder;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return iptvStageHoverGuard(
      isTelevision: isTelevision,
      onPointerInStage: onPointerInStage,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: stage.epoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: stage.shown,
            builder: (context, ch, _) {
              if (isTelevision) {
                return tvFocusStageBuilder(ch, epoch);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IptvPreviewStage(channel: ch, epoch: epoch, stage: stage),
                  const SizedBox(height: 16),
                  Expanded(child: IptvRailInfo(channel: ch)),
                  if (touchSelector) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('iptv-tablet-watch-fullscreen'),
                        onPressed: ch == null ? null : () => onWatch(ch),
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
                        stage.previewEnabled()
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
                        stage.previewEnabled()
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
}
