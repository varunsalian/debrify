import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/iptv_epg_service.dart';

/// The broadcast lower third shown on every live IPTV tune — the Flutter
/// counterpart of the native TV player's zap banner.
///
/// It replaces the old title/channel badge pair for live IPTV: those showed
/// the channel name twice (once per corner) and, worse, the right-hand badge
/// was painted from launch-time state that a zap never refreshed. This is
/// painted from the channel that is actually playing, so it cannot go stale.
///
/// The countdown and the elapsed rule are driven by [now] rather than an
/// internal clock read: the owner ticks once a second while the banner is up,
/// so the progress actually advances during the few seconds it is on screen.
class IptvZapBanner extends StatelessWidget {
  final IptvChannel channel;

  /// Guide data for [channel]. Null while the fetch is in flight — the banner
  /// says which of the two silences that is rather than leaving a gap.
  final EpgNowNext? epg;
  final bool epgLoading;

  /// The clock the countdown and elapsed rule are computed against.
  final DateTime now;

  /// Embedded mode: this is riding on top of the controls dock as one merged
  /// panel, so it drops its own scrim (the dock brings a background) and
  /// tightens the top padding. False when it floats over bare video on a zap.
  final bool flush;

  static const _accent = Color(0xFF00E5FF);

  const IptvZapBanner({
    super.key,
    required this.channel,
    required this.epg,
    required this.epgLoading,
    required this.now,
    this.flush = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // The native banner is laid out for a 10-foot viewport at fixed dp. On a
    // phone the same absolute sizes swallow the frame, so everything scales
    // off the width with a floor that keeps it legible on small screens.
    final scale = (width / 960).clamp(0.62, 1.0);
    double s(double v) => v * scale;

    // Side by side, the programme column eats the width the channel name
    // needs — on a phone it leaves the name truncated to a few characters.
    // Narrow viewports stack instead, which is also how the eye reads a
    // portrait screen.
    final narrow = width < 640;
    final programme = _buildProgramme(s, alignEnd: !narrow);

    return IgnorePointer(
      ignoring: true,
      child: Container(
        width: double.infinity,
        // The scrim darkens what sits under the text instead of drawing a card
        // the eye has to read around. Embedded, the dock is already opaque
        // underneath, and a second gradient would band against it.
        decoration: flush
            ? null
            : const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x0004060C),
                    Color(0xB804060C),
                    Color(0xF004060C),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                s(32),
                // Floating, the tall top padding is what lets the scrim fade
                // in above the text. Embedded there is no scrim to make room
                // for, and the space would just push the dock down.
                flush ? s(14) : (narrow ? s(28) : s(48)),
                s(32),
                s(16),
              ),
              child: narrow
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _LogoTile(channel: channel, size: s(68)),
                            SizedBox(width: s(20)),
                            Expanded(child: _buildIdentity(s)),
                          ],
                        ),
                        SizedBox(height: s(14)),
                        programme,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _LogoTile(channel: channel, size: s(68)),
                        SizedBox(width: s(20)),
                        Expanded(child: _buildIdentity(s)),
                        SizedBox(width: s(24)),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: s(380)),
                          child: programme,
                        ),
                      ],
                    ),
            ),
            _buildProgressRule(s),
          ],
        ),
      ),
    );
  }

  /// Number, name, and the category line. The number lives in its own accent
  /// slot, so the name is the RAW channel name — pairing it with a numbered
  /// display name is what makes the native banner read "7  CH 7  Sky Sports".
  Widget _buildIdentity(double Function(double) s) {
    final number = channel.channelNumber;
    final group = channel.group?.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (number != null) ...[
              Text(
                '$number',
                maxLines: 1,
                style: TextStyle(
                  color: _accent,
                  fontSize: s(27),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  height: 1.1,
                ),
              ),
              SizedBox(width: s(12)),
            ],
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(31),
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: s(5)),
        Row(
          children: [
            Text(
              '● LIVE',
              style: TextStyle(
                color: const Color(0xFFFF6470),
                fontSize: s(11.5),
                fontWeight: FontWeight.bold,
                letterSpacing: 0.12 * s(11.5),
              ),
            ),
            if (group != null && group.isNotEmpty) ...[
              SizedBox(width: s(9)),
              Expanded(
                child: Text(
                  '·  ${group.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.56),
                    fontSize: s(11.5),
                    letterSpacing: 0.09 * s(11.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The "what's on" column. Always present: a guideless channel gets a line
  /// naming the silence rather than a gap where the programme should be.
  ///
  /// [alignEnd] is the wide layout, where this sits opposite the identity;
  /// stacked underneath it on a narrow screen it reads left-aligned instead.
  Widget _buildProgramme(double Function(double) s, {required bool alignEnd}) {
    final nowProgramme = epg?.now;
    final nextProgramme = epg?.next;

    final String nowText;
    final Color nowColor;
    final FontWeight nowWeight;
    if (nowProgramme != null) {
      nowText = nowProgramme.title;
      nowColor = Colors.white;
      nowWeight = FontWeight.bold;
    } else {
      nowText = epgLoading ? 'Loading guide…' : 'No guide data';
      nowColor = Colors.white.withOpacity(0.42);
      nowWeight = FontWeight.normal;
    }

    final times = _timesLine(nowProgramme);
    final next = nextProgramme == null || nowProgramme == null
        ? null
        : 'Next  ${_formatTime(nextProgramme.start)}  ·  ${nextProgramme.title}';

    final align = alignEnd ? TextAlign.end : TextAlign.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          nowText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            color: nowColor,
            fontSize: s(17),
            fontWeight: nowWeight,
          ),
        ),
        if (times != null) ...[
          SizedBox(height: s(4)),
          Text(
            times,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: s(11.5),
              fontFamily: 'monospace',
            ),
          ),
        ],
        if (next != null) ...[
          SizedBox(height: s(4)),
          Text(
            next,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              color: Colors.white.withOpacity(0.52),
              fontSize: s(12.5),
            ),
          ),
        ],
      ],
    );
  }

  String? _timesLine(EpgProgramme? programme) {
    if (programme == null) return null;
    final runtime = programme.stop.difference(programme.start);
    if (runtime.inSeconds <= 0) return null;
    final remaining = programme.stop.difference(now);
    final tail = remaining > const Duration(minutes: 1)
        ? '  ·  ${_formatRemaining(remaining)} left'
        : '';
    return '${_formatTime(programme.start)} – '
        '${_formatTime(programme.stop)}$tail';
  }

  /// Screen-edge to screen-edge elapsed rule. It stays even with nothing to
  /// report — an empty track still reads as the edge of the broadcast, where
  /// hiding it would make the banner look truncated.
  ///
  /// Built by hand rather than with [LinearProgressIndicator]: that one draws
  /// a rounded, gapped Material 3 track and animates between values, neither
  /// of which suits a flat broadcast rule that steps once a second.
  Widget _buildProgressRule(double Function(double) s) {
    final programme = epg?.now;
    double value = 0;
    if (programme != null) {
      final runtime = programme.stop.difference(programme.start).inSeconds;
      if (runtime > 0) {
        final elapsed = now.difference(programme.start).inSeconds;
        value = (elapsed / runtime).clamp(0.0, 1.0);
      }
    }
    return Container(
      height: s(4),
      color: Colors.white.withOpacity(0.13),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value,
        heightFactor: 1,
        child: Container(color: _accent),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// "36 min" / "1 hr 12 min" — what is left of a programme's runtime.
  String _formatRemaining(Duration d) {
    final minutes = d.inMinutes < 0 ? 0 : d.inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours hr' : '$hours hr $rest min';
  }
}

/// Channel logo, falling back to the first letter of the channel name — both
/// while the image loads and when it fails outright.
class _LogoTile extends StatelessWidget {
  final IptvChannel channel;
  final double size;

  const _LogoTile({required this.channel, required this.size});

  @override
  Widget build(BuildContext context) {
    final letter = channel.name.isEmpty
        ? '?'
        : channel.name.characters.first.toUpperCase();
    final logoUrl = channel.logoUrl;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.09),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.16), width: 1),
      ),
      child: logoUrl == null || logoUrl.isEmpty
          ? _letterTile(letter)
          : Image.network(
              logoUrl,
              // Keyed by URL so a zap never leaves the previous channel's logo
              // sitting under the new channel's name while the next one loads.
              key: ValueKey(logoUrl),
              fit: BoxFit.contain,
              gaplessPlayback: false,
              errorBuilder: (_, __, ___) => _letterTile(letter),
              frameBuilder: (_, child, frame, wasSync) {
                if (frame == null && !wasSync) return _letterTile(letter);
                return child;
              },
            ),
    );
  }

  Widget _letterTile(String letter) => Center(
    child: Text(
      letter,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.44,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
