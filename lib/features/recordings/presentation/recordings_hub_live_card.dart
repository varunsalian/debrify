import 'package:debrify/features/recordings/presentation/recordings_hub_buttons.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

const _kCard = Color(0xFF10142A);

// ── Recording-now card ──────────────────────────────────────────────────────
class _LiveCard extends StatelessWidget {
  final String channelName;
  final DateTime startedAt;
  final ValueNotifier<DateTime> now;
  final int Function() bytesOf;
  final String Function(int) fmtBytes;
  final String Function(Duration) fmtElapsed;
  final bool autofocus;
  final VoidCallback onStop;

  const _LiveCard({
    required this.channelName,
    required this.startedAt,
    required this.now,
    required this.bytesOf,
    required this.fmtBytes,
    required this.fmtElapsed,
    required this.autofocus,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: kRecordingsHubRec.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: kRecordingsHubRec.withValues(alpha: 0.07),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          const _RecDot(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<DateTime>(
                  valueListenable: now,
                  builder: (context, current, _) {
                    final elapsed = current.difference(startedAt);
                    final bytes = bytesOf();
                    return Text(
                      '${fmtElapsed(elapsed.isNegative ? Duration.zero : elapsed)}'
                      '${bytes > 0 ? ' · ${fmtBytes(bytes)}' : ''}',
                      style: TextStyle(
                        color: kRecordingsHubRec.withValues(alpha: 0.9),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RecordingsHubHubButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            danger: true,
            autofocus: autofocus,
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}

typedef RecordingsHubLiveCard = _LiveCard;

/// The REC dot: pulses on phone/desktop, static on TV (house rule — no new
/// standing animations on TV hardware).
class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!PlatformUtil.isTelevision) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
        lowerBound: 0.35,
        upperBound: 1.0,
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kRecordingsHubRec,
        boxShadow: [
          BoxShadow(
            color: kRecordingsHubRec.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
    );
    final controller = _controller;
    if (controller == null) return dot;
    return FadeTransition(opacity: controller, child: dot);
  }
}
