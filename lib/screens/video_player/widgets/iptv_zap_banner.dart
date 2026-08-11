import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/iptv_epg_service.dart';
import '../../../widgets/iptv/styles/iptv_style.dart';
import 'player_guide_style.dart';

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
///
/// [style] picks the look (see [PlayerGuideStyle]). `classic` takes the
/// untouched legacy paint path; the styled branches own their whole visual
/// tree and read only their token colors.
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

  final PlayerGuideStyle style;

  /// Tokens for [style], resolved ONCE by the owner (the player screen) —
  /// null takes the classic path. Passed alongside [style] rather than looked
  /// up per build, per the plan's wiring contract.
  final IptvStyleTokens? tokens;

  /// Whether this live channel is being recorded right now. Styled looks
  /// show a REC tag beside LIVE; classic ignores it (verbatim legacy paint).
  final bool isRecording;

  static const _accent = Color(0xFF00E5FF);

  const IptvZapBanner({
    super.key,
    required this.channel,
    required this.epg,
    required this.epgLoading,
    required this.now,
    this.flush = false,
    this.style = PlayerGuideStyle.classic,
    this.tokens,
    this.isRecording = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    if (style == PlayerGuideStyle.classic || t == null) {
      return _buildClassic(context);
    }
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 960).clamp(0.62, 1.0);
    double s(double v) => v * scale;
    final child = switch (style) {
      // Spotlight rides the glass banner shape — its tokens (white ink,
      // crimson status) restyle it into the monochrome look on their own.
      PlayerGuideStyle.glass ||
      PlayerGuideStyle.spotlight => _buildGlass(t, s, width),
      PlayerGuideStyle.edition => _buildEdition(t, s),
      PlayerGuideStyle.console => _buildConsole(t, s),
      PlayerGuideStyle.classic => throw StateError('unreachable'),
    };
    return IgnorePointer(ignoring: true, child: child);
  }

  // ─── Classic — the legacy banner, byte-for-byte ────────────────────────────

  Widget _buildClassic(BuildContext context) {
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

  // ─── Cinema Glass — floating island card / flush glass band ───────────────

  Widget _buildGlass(IptvStyleTokens t, double Function(double) s, double width) {
    final narrow = width < 640;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            s(20),
            flush ? s(14) : s(18),
            s(20),
            s(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StyledLogoTile(channel: channel, size: s(60), tokens: t),
              SizedBox(width: s(16)),
              Expanded(child: _glassIdentityAndProgramme(t, s)),
            ],
          ),
        ),
        Padding(
          padding: flush
              ? EdgeInsets.zero
              : EdgeInsets.fromLTRB(s(20), 0, s(20), s(16)),
          child: _styledProgressRule(
            s,
            height: s(3),
            track: t.hairline2,
            fill: t.accent,
            rounded: true,
          ),
        ),
      ],
    );

    if (flush) {
      // The dock brings the surface; the banner is just the content band.
      return SizedBox(width: double.infinity, child: content);
    }
    // Floating: an inset island card, left-anchored like a broadcast bug,
    // over a much lighter scrim than classic — the video stays visible.
    final islandMaxWidth = narrow
        ? (width - s(56)).clamp(s(220), s(760))
        : s(760);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x000A0C12), Color(0x730A0C12)],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          margin: EdgeInsets.fromLTRB(s(28), s(40), s(28), s(24)),
          constraints: BoxConstraints(maxWidth: islandMaxWidth),
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(s(22)),
            border: Border.all(color: t.hairline2, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      ),
    );
  }

  Widget _glassIdentityAndProgramme(
    IptvStyleTokens t,
    double Function(double) s,
  ) {
    final number = channel.channelNumber;
    final group = channel.group?.trim();
    final nowProgramme = epg?.now;
    final nowText = nowProgramme?.title ?? _silenceLine();
    final times = _timesLine(nowProgramme);
    final next = _nextLine();

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
                  color: t.fg,
                  fontSize: s(20),
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.1,
                ),
              ),
              SizedBox(width: s(10)),
            ],
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.fg,
                  fontSize: s(22),
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            SizedBox(width: s(12)),
            _liveRecTags(t, s, size: 11),
          ],
        ),
        SizedBox(height: s(6)),
        Text(
          nowText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: nowProgramme != null ? t.fgMid : t.fgFaint,
            fontSize: s(15),
            fontWeight: nowProgramme != null
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
        if (times != null || (group != null && group.isNotEmpty)) ...[
          SizedBox(height: s(3)),
          Text(
            [
              if (times != null) times,
              if (group != null && group.isNotEmpty) group.toUpperCase(),
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.fgDim,
              fontSize: s(11.5),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (next != null) ...[
          SizedBox(height: s(3)),
          Text(
            next,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.fgFaint, fontSize: s(11.5)),
          ),
        ],
      ],
    );
  }

  // ─── Midnight Edition — editorial full-width ink band ─────────────────────

  Widget _buildEdition(IptvStyleTokens t, double Function(double) s) {
    final number = channel.channelNumber;
    final group = channel.group?.trim();
    final nowProgramme = epg?.now;
    // Editorial hierarchy: the PROGRAMME is the headline and the channel is
    // the byline. A guideless channel promotes its name to the headline.
    final headline = nowProgramme?.title ?? channel.name;
    final byline = nowProgramme == null
        ? _silenceLine()
        : [
            channel.name,
            if (_timesLine(nowProgramme) != null) _timesLine(nowProgramme)!,
          ].join('   —   ');
    final next = _nextLine();

    final kicker = Row(
      children: [
        Text(
          [
            if (number != null) 'CH $number',
            'LIVE',
          ].join('  ·  '),
          style: TextStyle(
            color: t.fgDim,
            fontSize: s(11),
            fontFamily: t.captionFamily,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.18 * s(11),
          ),
        ),
        if (isRecording)
          Text(
            '  ● REC',
            style: TextStyle(
              color: t.rec,
              fontSize: s(11),
              fontFamily: t.captionFamily,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.18 * s(11),
            ),
          ),
        if (group != null && group.isNotEmpty)
          Expanded(
            child: Text(
              '  ·  ${group.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.fgFaint,
                fontSize: s(11),
                fontFamily: t.captionFamily,
                fontStyle: FontStyle.italic,
                letterSpacing: 0.18 * s(11),
              ),
            ),
          ),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: flush
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0x000D0B09), t.bg],
                stops: const [0.0, 0.62],
              ),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              s(36),
              flush ? s(14) : s(44),
              s(36),
              s(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!flush) ...[
                  Container(height: 1, color: t.hairline2),
                  SizedBox(height: s(12)),
                ],
                kicker,
                SizedBox(height: s(7)),
                Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.fg,
                    fontSize: s(27),
                    fontFamily: t.headlineFamily,
                    height: 1.12,
                  ),
                ),
                SizedBox(height: s(6)),
                Text(
                  byline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.fgDim,
                    fontSize: s(12.5),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (next != null) ...[
                  SizedBox(height: s(4)),
                  Text(
                    next,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.fgFaint,
                      fontSize: s(12),
                      fontFamily: t.captionFamily,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _styledProgressRule(
            s,
            height: s(2),
            track: t.hairline,
            fill: t.fg,
            rounded: false,
          ),
        ],
      ),
    );
  }

  // ─── Master Control — black instrument strip ──────────────────────────────

  Widget _buildConsole(IptvStyleTokens t, double Function(double) s) {
    final number = channel.channelNumber;
    final nowProgramme = epg?.now;
    final nowText = nowProgramme?.title ?? _silenceLine();
    final times = _timesLine(nowProgramme);
    final next = _nextLine();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (number != null) ...[
              Text(
                '$number'.padLeft(3, '0'),
                maxLines: 1,
                style: TextStyle(
                  color: t.accent,
                  fontSize: s(19),
                  fontWeight: FontWeight.w700,
                  fontFamily: t.monoFamily,
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
                  color: t.fg,
                  fontSize: s(20),
                  fontWeight: FontWeight.w700,
                  fontFamily: t.nameFamily,
                  height: 1.1,
                ),
              ),
            ),
            SizedBox(width: s(12)),
            _liveRecTags(t, s, size: 10.5, mono: true),
          ],
        ),
        SizedBox(height: s(7)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'NOW',
              style: TextStyle(
                color: t.fgFaint,
                fontSize: s(10),
                fontWeight: FontWeight.w700,
                fontFamily: t.monoFamily,
                letterSpacing: 0.2 * s(10),
              ),
            ),
            SizedBox(width: s(10)),
            Expanded(
              child: Text(
                nowText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: nowProgramme != null ? t.fg : t.fgFaint,
                  fontSize: s(14.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (times != null) ...[
              SizedBox(width: s(14)),
              Text(
                times,
                maxLines: 1,
                style: TextStyle(
                  color: t.fgDim,
                  fontSize: s(11),
                  fontFamily: t.monoFamily,
                ),
              ),
            ],
          ],
        ),
        if (next != null) ...[
          SizedBox(height: s(4)),
          Text(
            next.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.fgFaint,
              fontSize: s(10.5),
              fontFamily: t.monoFamily,
            ),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      decoration: flush
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0x00050505), t.bg],
                stops: const [0.0, 0.55],
              ),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              s(32),
              flush ? s(14) : s(40),
              s(32),
              s(14),
            ),
            // The amber rule rides the content block as a left border — no
            // IntrinsicHeight measurement pass on the 1s banner tick.
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: t.accent, width: s(2.5)),
                ),
              ),
              padding: EdgeInsets.only(left: s(16)),
              child: content,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(s(32), 0, s(32), s(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SizedBox(
                    height: s(6),
                    child: CustomPaint(
                      painter: _TickMeterPainter(
                        value: _progressValue(),
                        elapsed: t.accent,
                        rest: t.hairline2,
                      ),
                    ),
                  ),
                ),
                if (nowProgramme != null) ...[
                  SizedBox(width: s(10)),
                  Text(
                    _formatTime(nowProgramme.stop),
                    style: TextStyle(
                      color: t.fgDim,
                      fontSize: s(10.5),
                      fontFamily: t.monoFamily,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Styled shared pieces ─────────────────────────────────────────────────

  /// `● LIVE` (+ `● REC` while recording) in token colors.
  Widget _liveRecTags(
    IptvStyleTokens t,
    double Function(double) s, {
    required double size,
    bool mono = false,
  }) {
    final family = mono ? t.monoFamily : '';
    TextStyle tag(Color c) => TextStyle(
      color: c,
      fontSize: s(size),
      fontWeight: FontWeight.bold,
      fontFamily: family.isEmpty ? null : family,
      letterSpacing: 0.12 * s(size),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('● LIVE', style: tag(t.live)),
        if (isRecording) ...[
          SizedBox(width: s(10)),
          Text('● REC', style: tag(t.rec)),
        ],
      ],
    );
  }

  String _silenceLine() => epgLoading ? 'Loading guide…' : 'No guide data';

  String? _nextLine() {
    final nowProgramme = epg?.now;
    final nextProgramme = epg?.next;
    if (nextProgramme == null || nowProgramme == null) return null;
    return 'Next  ${_formatTime(nextProgramme.start)}  ·  ${nextProgramme.title}';
  }

  double _progressValue() {
    final programme = epg?.now;
    if (programme == null) return 0;
    final runtime = programme.stop.difference(programme.start).inSeconds;
    if (runtime <= 0) return 0;
    final elapsed = now.difference(programme.start).inSeconds;
    return (elapsed / runtime).clamp(0.0, 1.0);
  }

  /// The styled elapsed rule — same hand-built semantics as the classic one
  /// (flat, steps once a second), parameterized on token colors.
  Widget _styledProgressRule(
    double Function(double) s, {
    required double height,
    required Color track,
    required Color fill,
    required bool rounded,
  }) {
    final rule = Container(
      height: height,
      color: rounded ? null : track,
      decoration: rounded
          ? BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(height),
            )
          : null,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: _progressValue(),
        heightFactor: 1,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: rounded ? BorderRadius.circular(height) : null,
          ),
        ),
      ),
    );
    return rule;
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

/// The token-tinted logo tile the styled looks use: calm `selectedTint` fill
/// + hairline border instead of the classic white-gradient glass, letter
/// fallback in the style's foreground.
class _StyledLogoTile extends StatelessWidget {
  final IptvChannel channel;
  final double size;
  final IptvStyleTokens tokens;

  const _StyledLogoTile({
    required this.channel,
    required this.size,
    required this.tokens,
  });

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
        borderRadius: BorderRadius.circular(size * 0.24),
        color: tokens.selectedTint,
        border: Border.all(color: tokens.hairline2, width: 1),
      ),
      child: logoUrl == null || logoUrl.isEmpty
          ? _letterTile(letter)
          : Image.network(
              logoUrl,
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
        color: tokens.fg,
        fontSize: size * 0.44,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

/// Master Control's elapsed meter: a row of instrument ticks, elapsed ones
/// in amber. Repaints only when the once-a-second banner tick moves it.
class _TickMeterPainter extends CustomPainter {
  final double value;
  final Color elapsed;
  final Color rest;

  const _TickMeterPainter({
    required this.value,
    required this.elapsed,
    required this.rest,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const tickWidth = 3.0;
    const gap = 3.0;
    final count = ((size.width + gap) / (tickWidth + gap)).floor();
    if (count <= 0) return;
    final lit = (value * count).round();
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      paint.color = i < lit ? elapsed : rest;
      final x = i * (tickWidth + gap);
      canvas.drawRect(Rect.fromLTWH(x, 0, tickWidth, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_TickMeterPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.elapsed != elapsed ||
      oldDelegate.rest != rest;
}
