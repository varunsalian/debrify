import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../utils/platform_util.dart';
import '../services/playback_ui_clock.dart';

/// Debrify TV's channel identity, in the Spotlight grammar — replaces the
/// two legacy corner badges (top-left title, top-right "CH 05 • NAME") with
/// one lower-third: a channel plate (numeral + name) beside the item that's
/// actually playing.
///
/// Two presentations, same contract as [IptvZapBanner]:
///  - floating (`flush: false`): the bottom lower-third raised on tune/zap,
///    with its own scrim gradient; the host times its visibility.
///  - flush (`flush: true`): a compact identity row the transport bar embeds
///    above its own controls — so raising the bar IS the recall gesture.
///
/// No color anywhere: Debrify TV isn't live, so even the status crimson
/// stays away. Glass, hairline, white ink.
class DebrifyTvBanner extends StatelessWidget {
  final int? channelNumber;
  final String? channelName;

  /// The playing item's display title; null hides the line (the
  /// `showVideoTitle` launch flag off).
  final String? title;

  final ValueListenable<PlaybackUiClockValue> clock;

  /// False when the session hides the seekbar (`hideSeekbar`) — Debrify TV
  /// deliberately keeps runtimes a surprise there, and the banner must not
  /// leak what the dock hides.
  final bool showProgress;

  final bool flush;

  const DebrifyTvBanner({
    super.key,
    required this.channelNumber,
    required this.channelName,
    required this.title,
    required this.clock,
    required this.showProgress,
    required this.flush,
  });

  static const _ink = Colors.white;

  bool get _hasPlate =>
      channelNumber != null || (channelName?.trim().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    if (!_hasPlate && (title == null || title!.trim().isEmpty)) {
      return const SizedBox.shrink();
    }
    return flush ? _buildFlush(context) : _buildFloating(context);
  }

  // ── Floating lower-third ──

  Widget _buildFloating(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Laid out for a 10-foot viewport; phones scale down with a floor.
    final scale = (width / 960).clamp(0.62, 1.0);
    double s(double v) => v * scale;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(s(44), s(70), s(44), s(34)),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xC7000000)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_hasPlate) ...[
            _plate(s),
            SizedBox(width: s(20)),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DEBRIFY TV',
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.42),
                    fontSize: s(9.5),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                  ),
                ),
                if (title != null && title!.trim().isNotEmpty) ...[
                  SizedBox(height: s(5)),
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink,
                      fontSize: s(25),
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 14),
                      ],
                    ),
                  ),
                ],
                if (showProgress) ...[
                  SizedBox(height: s(10)),
                  _progressRow(s),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _plate(double Function(double) s) {
    final name = channelName?.trim();
    final card = Container(
      constraints: BoxConstraints(minWidth: s(84)),
      padding: EdgeInsets.fromLTRB(s(16), s(11), s(16), s(9)),
      decoration: BoxDecoration(
        color: PlatformUtil.isAndroidTvCached
            ? const Color(0xF5101012)
            : const Color(0xFF101012).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ink.withValues(alpha: 0.14), width: 0.75),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (channelNumber != null)
            Text(
              '${channelNumber! < 0 ? 0 : channelNumber}'.padLeft(2, '0'),
              style: TextStyle(
                color: _ink,
                fontSize: s(30),
                height: 1.0,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          if (name != null && name.isNotEmpty) ...[
            SizedBox(height: s(5)),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: s(116)),
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.55),
                  fontSize: s(9.5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (PlatformUtil.isAndroidTvCached) return card;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: card,
      ),
    );
  }

  Widget _progressRow(double Function(double) s) {
    return ValueListenableBuilder<PlaybackUiClockValue>(
      valueListenable: clock,
      builder: (context, v, _) {
        final total = v.duration.inMilliseconds;
        if (total <= 0) return const SizedBox.shrink();
        final progress = (v.position.inMilliseconds / total).clamp(0.0, 1.0);
        return Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 2.5,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (progress * 1000).round().clamp(0, 1000),
                        child: const ColoredBox(color: _ink),
                      ),
                      Expanded(
                        flex: (1000 - (progress * 1000).round()).clamp(0, 1000),
                        child: ColoredBox(
                          color: _ink.withValues(alpha: 0.16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: s(10)),
            Text(
              '${_fmt(v.position)} / ${_fmt(v.duration)}',
              style: TextStyle(
                color: _ink.withValues(alpha: 0.45),
                fontSize: s(10.5),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Flush — the identity row the transport bar embeds ──

  Widget _buildFlush(BuildContext context) {
    final name = channelName?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (_hasPlate) ...[
            // Flexible + ellipsis: an imported channel name of arbitrary
            // length must squeeze, not overflow a phone-width bar.
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: _ink.withValues(alpha: 0.30),
                    width: 0.75,
                  ),
                ),
                child: Text(
                  [
                    if (channelNumber != null)
                      'CH ${'${channelNumber! < 0 ? 0 : channelNumber}'.padLeft(2, '0')}',
                    if (name != null && name.isNotEmpty) name.toUpperCase(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.75),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (title != null && title!.trim().isNotEmpty)
            Expanded(
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}
