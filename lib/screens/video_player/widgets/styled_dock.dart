/// The `two_tier` dock — everything `classic` is not.
///
/// Lives in its own file so `Controls.build` can branch to it in one
/// expression and leave the legacy tree untouched. That is the whole
/// compatibility strategy: `classic` cannot enter this code, so it cannot
/// regress.
///
/// Three arrangements, chosen from the viewport (never persisted):
/// `narrow` is a single row, `regular` is two tiers, `wide` is zoned.
///
/// See `plan/PLAYER_DOCK_STYLES_PLAN.md` §3.
library;

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart' show ValueListenable;

import '../models/gesture_state.dart';
import '../services/playback_ui_clock.dart';
import '../utils/aspect_mode_utils.dart';
import 'dock_style.dart';
import 'dock_widgets.dart';

/// One control the dock can offer, with its availability already resolved.
class _Tool {
  final IconData icon;
  final String label;
  final String? value;
  final bool active;

  /// Overrides the palette accent for semantic state — today only the record
  /// red, which must look the same in every palette.
  final Color? tint;
  final VoidCallback onPressed;
  const _Tool(
    this.icon,
    this.label,
    this.onPressed, {
    this.value,
    this.active = false,
    this.tint,
  });
}

class StyledDock extends StatelessWidget {
  final DockMetrics metrics;
  final DockPalette palette;
  final DockArrangement arrangement;

  final String title;
  final String? subtitle;
  final Widget? infoPanel;

  /// The dock takes the clock rather than a position/duration pair, matching
  /// the legacy path — only the scrub row rebuilds on a tick, not the whole
  /// dock.
  final ValueListenable<PlaybackUiClockValue> clock;
  final bool isPlaying;

  final VoidCallback onPlayPause;
  final VoidCallback onBack;
  final VoidCallback onAspect;
  final VoidCallback onSpeed;
  final VoidCallback onSleepTimer;
  final VoidCallback onShowTracks;
  final VoidCallback onShowPlaylist;
  final VoidCallback onRandom;
  final VoidCallback onRotate;
  final VoidCallback onSeekBarChangedStart;
  final ValueChanged<double> onSeekBarChanged;
  final VoidCallback onSeekBarChangeEnd;

  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNextChannel;
  final VoidCallback? onShowGuide;
  final VoidCallback? onShowIptvChannels;
  final VoidCallback? onShowStremioSources;
  final VoidCallback? onRecord;
  final VoidCallback? onPip;

  final bool hasNext;
  final bool hasPrevious;
  final bool hasNextChannel;
  final bool hasGuide;
  final bool hasIptvChannels;
  final bool hasStremioSources;
  final bool hasPlaylist;
  final bool hasRecord;
  final bool isRecording;
  final bool showPipButton;

  final bool hideSeekbar;
  final bool hideOptions;
  final bool hideBackButton;
  final bool hideSpeed;
  final bool hideRandom;

  /// Supplied by the host rather than read from `PlatformUtil` here, so a
  /// desktop test host can still exercise the control.
  final bool showRotate;
  final bool isLandscape;

  final String? sleepTimerLabel;
  final double speed;
  final AspectMode aspectMode;

  /// Reports the BOTTOM UNIT's height — not this widget's, whose root is a
  /// full-screen Stack. Measuring the Stack would report the viewport and
  /// protect the entire screen from gestures.
  final void Function(double, int)? onDockExtent;

  /// The host's geometry generation, handed to both reporters.
  /// 0..1. The wide dock anchors its play button with a volume control, the
  /// way the design does; without it the transport floats alone.
  final double volume;
  final ValueChanged<double>? onVolumeChanged;

  /// Only Windows/Linux drive fullscreen through windowManager; elsewhere the
  /// OS owns it, so the control would be a lie.
  final bool showFullscreen;
  final VoidCallback? onFullscreen;

  final int geometryGeneration;

  /// Separate from [geometryGeneration]: the panel's structure can change
  /// without the dock's geometry inputs changing, and vice versa.
  final int infoPanelGeneration;

  /// Reports the info panel's measured height — the second pass of the
  /// two-pass contract. Until it fires the budget reserves the bound.
  final void Function(double, int)? onInfoPanelExtent;

  const StyledDock({
    super.key,
    required this.metrics,
    required this.palette,
    required this.arrangement,
    required this.title,
    required this.subtitle,
    required this.infoPanel,
    required this.clock,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onBack,
    required this.onAspect,
    required this.onSpeed,
    required this.onSleepTimer,
    required this.onShowTracks,
    required this.onShowPlaylist,
    required this.onRandom,
    required this.onRotate,
    required this.onSeekBarChangedStart,
    required this.onSeekBarChanged,
    required this.onSeekBarChangeEnd,
    required this.speed,
    required this.aspectMode,
    required this.isLandscape,
    required this.hideSeekbar,
    required this.hideOptions,
    required this.hideBackButton,
    this.onNext,
    this.onPrevious,
    this.onNextChannel,
    this.onShowGuide,
    this.onShowIptvChannels,
    this.onShowStremioSources,
    this.onRecord,
    this.onPip,
    this.hasNext = false,
    this.hasPrevious = false,
    this.hasNextChannel = false,
    this.hasGuide = false,
    this.hasIptvChannels = false,
    this.hasStremioSources = false,
    this.hasPlaylist = false,
    this.hasRecord = false,
    this.isRecording = false,
    this.showPipButton = false,
    this.hideSpeed = false,
    this.hideRandom = false,
    this.showRotate = true,
    this.sleepTimerLabel,
    this.onDockExtent,
    this.onInfoPanelExtent,
    this.volume = 1.0,
    this.onVolumeChanged,
    this.showFullscreen = false,
    this.onFullscreen,
    this.geometryGeneration = 0,
    this.infoPanelGeneration = 0,
  });

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// The canonical label — the same helper the legacy dock uses, so the two
  /// styles never disagree about what a mode is called.
  String get _aspectLabel => AspectModeUtils.aspectModeToString(aspectMode);

  /// Every available tool, in **availability-priority order**.
  ///
  /// `Controls` has no live/VOD input and the guards are independent — live
  /// IPTV can have Channels without Guide, playlist VOD usually has Episodes
  /// without Sources. A mode-based mapping collapsed to two buttons in all
  /// those cases; this cannot, because the tail (Subtitles, Aspect, Sleep) is
  /// unconditional, so three are always found.
  ///
  /// Record and Guide lead because they are the most session-specific and the
  /// least reachable elsewhere.
  List<_Tool> _tools() {
    return [
      if (hasRecord && onRecord != null)
        _Tool(
          isRecording
              ? Icons.stop_circle_rounded
              : Icons.fiber_manual_record_rounded,
          isRecording ? 'Stop recording' : 'Record',
          onRecord!,
          active: isRecording,
          // Semantic, never the palette accent.
          tint: isRecording ? DockPalette.record : null,
        ),
      if (hasGuide && onShowGuide != null)
        _Tool(Icons.grid_view_rounded, 'Guide', onShowGuide!),
      // Renamed from "Guide": the legacy dock rendered that word twice, side
      // by side, for two different destinations.
      if (hasIptvChannels && onShowIptvChannels != null)
        _Tool(
          Icons.calendar_view_week_rounded,
          'Channels',
          onShowIptvChannels!,
        ),
      if (hasNextChannel && onNextChannel != null)
        _Tool(Icons.tv_rounded, 'Next channel', onNextChannel!),
      if (hasPlaylist)
        _Tool(Icons.playlist_play_rounded, 'Episodes', onShowPlaylist),
      if (hasStremioSources && onShowStremioSources != null)
        _Tool(Icons.swap_horiz_rounded, 'Sources', onShowStremioSources!),
      _Tool(Icons.subtitles_rounded, 'Subtitles & audio', onShowTracks),
      _Tool(
        Icons.aspect_ratio_rounded,
        'Aspect ratio',
        onAspect,
        value: _aspectLabel,
      ),
      _Tool(
        sleepTimerLabel == null
            ? Icons.bedtime_outlined
            : Icons.bedtime_rounded,
        'Sleep timer',
        onSleepTimer,
        value: sleepTimerLabel,
        active: sleepTimerLabel != null,
      ),
      if (!hideSpeed)
        _Tool(
          Icons.speed_rounded,
          'Playback speed',
          onSpeed,
          value: '${speed}x',
        ),
      if (!hideRandom)
        _Tool(Icons.shuffle_rounded, 'Play something random', onRandom),
      // Meaningless on desktop, where the window does not rotate. Classic
      // still shows it unconditionally.
      if (showRotate)
        _Tool(
          Icons.screen_rotation_rounded,
          isLandscape ? 'Lock to portrait' : 'Lock to landscape',
          onRotate,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tools = _tools();
    return Stack(
      children: [
        // The wide dock carries identity in its centre zone, so a top bar
        // title there would render the same string twice — which is exactly
        // the duplication this redesign set out to remove.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _topBar(context, showTitle: !_centreIdentityVisible),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: onDockExtent == null
              ? _bottomUnit(context, tools)
              : DockExtentReporter(
                  onExtent: onDockExtent!,
                  generation: geometryGeneration,
                  child: _bottomUnit(context, tools),
                ),
        ),
      ],
    );
  }

  /// True only when the wide centre zone is actually on screen to carry the
  /// title. `hideOptions` removes the whole controls row, so without this the
  /// identity vanished from both places at once.
  bool get _centreIdentityVisible =>
      arrangement == DockArrangement.wide &&
      !hideOptions &&
      (title.isNotEmpty || (subtitle?.isNotEmpty ?? false));

  Widget _topBar(BuildContext context, {bool showTitle = true}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.padX * 1.8,
        vertical: metrics.padY,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.scrim, const Color(0x00040610)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (!hideBackButton)
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: palette.ink),
                iconSize: metrics.icon,
                tooltip: 'Back',
                onPressed: onBack,
              ),
            SizedBox(width: metrics.gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTitle && title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: metrics.label * 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (showTitle && subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.inkDim,
                        fontSize: metrics.label,
                      ),
                    ),
                ],
              ),
            ),
            // PiP lives here, not in the tools row: legacy keeps it reachable
            // independently of `hideOptions`, and burying it in the tools row
            // would lose it whenever options are hidden.
            if (showPipButton && onPip != null)
              IconButton(
                icon: Icon(
                  Icons.picture_in_picture_alt_rounded,
                  color: palette.ink,
                ),
                iconSize: metrics.icon,
                tooltip: 'Picture in picture',
                onPressed: onPip,
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomUnit(BuildContext context, List<_Tool> tools) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [palette.scrim, const Color(0x00040610)],
          stops: const [0.12, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (infoPanel != null)
              onInfoPanelExtent == null
                  ? infoPanel!
                  : DockExtentReporter(
                      onExtent: onInfoPanelExtent!,
                      generation: infoPanelGeneration,
                      child: infoPanel!,
                    ),
            if (!hideOptions)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The wide bar is genuinely edge-to-edge, so it is mounted
                  // OUTSIDE the dock's horizontal padding rather than trying
                  // to cancel it (negative padding is not a thing).
                  if (arrangement == DockArrangement.wide && !hideSeekbar)
                    Padding(
                      padding: EdgeInsets.only(top: metrics.padY),
                      child: _scrubber(context, bleed: true),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      metrics.padX * 1.8,
                      arrangement == DockArrangement.wide ? 0 : metrics.padY,
                      metrics.padX * 1.8,
                      metrics.padY * 1.5,
                    ),
                    child: switch (arrangement) {
                      DockArrangement.narrow => _narrow(context, tools),
                      DockArrangement.regular => _twoTier(context, tools),
                      DockArrangement.wide => _wide(context, tools),
                    },
                  ),
                ],
              )
            else if (!hideSeekbar)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.padX * 1.8,
                  metrics.padY,
                  metrics.padX * 1.8,
                  metrics.padY * 1.5,
                ),
                child: _scrubber(context),
              ),
          ],
        ),
      ),
    );
  }

  /// One row: transport, then the highest-priority tools, then More.
  ///
  /// Degrades in stages rather than jumping straight to a scrolling strip,
  /// because each stage costs the user less than the next: shrinking gaps is
  /// invisible, dropping a tool costs one extra tap through More, hiding
  /// labels costs recognisability, and scrolling hides things entirely.
  Widget _narrow(BuildContext context, List<_Tool> tools) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hideSeekbar) _scrubber(context),
        SizedBox(height: metrics.gap),
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            // Rough per-chip cost: icon + padding, plus ~6.5px per character
            // at the label size. Deliberately an over-estimate — the ladder
            // should step down early rather than overflow.
            // Includes the icon-to-label gap and the LIVE text scaler; an
            // earlier version omitted both and so kept three labelled tools
            // on rows that then had to scroll. 0.62em per character is a
            // deliberate over-estimate for wide glyphs.
            final scaledLabel = MediaQuery.textScalerOf(
              context,
            ).scale(metrics.label);
            double chipWidth(_Tool t, bool labelled) =>
                metrics.icon +
                metrics.padX * 2 +
                (labelled
                    ? metrics.gap * 0.75 + t.label.length * scaledLabel * 0.62
                    : 0);
            final transportWidth =
                (hasPrevious && onPrevious != null ? metrics.target : 0) +
                metrics.target * 1.32 +
                (hasNext && onNext != null ? metrics.target : 0) +
                metrics.gap * 3;
            final moreWidth = metrics.icon + metrics.padX * 2 + 30;

            bool fits(int count, bool labelled, double gap) {
              var width = transportWidth + moreWidth + gap * (count + 1);
              for (final t in tools.take(count)) {
                width += chipWidth(t, labelled);
              }
              return width <= available;
            }

            // Step down in order until something fits.
            var count = 3;
            var labelled = true;
            var gap = metrics.gap;
            if (!fits(count, labelled, gap)) {
              gap = metrics.gap * 0.75; // 1: tighten gaps
            }
            if (!fits(count, labelled, gap)) {
              count = 2; // 2: three tools become two
            }
            if (!fits(count, labelled, gap)) {
              labelled = false; // 3: labels become icons
            }
            if (!fits(count, labelled, gap)) {
              count = 1; // 4: one tool plus More
            }
            // 5 (last resort): whatever remains scrolls, with an edge fade.

            final promoted = tools.take(count).toList();
            return Row(
              children: [
                ..._transport(),
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0x00000000), Color(0xFF000000)],
                      stops: [0.0, 0.06],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        children: [
                          for (final tool in promoted) ...[
                            DockChip(
                              icon: tool.icon,
                              label: tool.label,
                              showLabel: labelled,
                              active: tool.active,
                              tint: tool.tint,
                              onPressed: tool.onPressed,
                              metrics: metrics,
                              palette: palette,
                            ),
                            SizedBox(width: gap),
                          ],
                          DockChip(
                            icon: Icons.more_horiz_rounded,
                            label: 'More',
                            active: true,
                            onPressed: () => _openOverflow(context, tools),
                            metrics: metrics,
                            palette: palette,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Centred transport above the scrubber, tools wrapping below.
  Widget _twoTier(BuildContext context, List<_Tool> tools) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _transport(),
        ),
        SizedBox(height: metrics.gap),
        if (!hideSeekbar) _scrubber(context),
        SizedBox(height: metrics.gap),
        Wrap(
          spacing: metrics.gap,
          runSpacing: metrics.gap,
          alignment: arrangement == DockArrangement.wide
              ? WrapAlignment.center
              : WrapAlignment.start,
          children: [
            for (final tool in tools)
              DockChip(
                icon: tool.icon,
                label: tool.value == null
                    ? tool.label
                    : '${tool.label} · ${tool.value}',
                active: tool.active,
                tint: tool.tint,
                onPressed: tool.onPressed,
                metrics: metrics,
                palette: palette,
              ),
          ],
        ),
      ],
    );
  }

  /// Zones: transport + time on the left, what's playing centred, icon-only
  /// tools on the right. Nothing scrolls, and the labels move into tooltips
  /// because a pointer can hover but a thumb cannot.
  Widget _wide(BuildContext context, List<_Tool> tools) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ..._transport(),
            if (onVolumeChanged != null) ...[
              SizedBox(width: metrics.gap),
              _volume(context),
            ],
            SizedBox(width: metrics.gap),
            _timeReadout(),
            SizedBox(width: metrics.gap * 1.5),
            Expanded(child: _nowPlaying()),
            SizedBox(width: metrics.gap * 1.5),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    for (final tool in tools) ...[
                      DockChip(
                        icon: tool.icon,
                        label: tool.value == null
                            ? tool.label
                            : '${tool.label} · ${tool.value}',
                        showLabel: false,
                        active: tool.active,
                        tint: tool.tint,
                        onPressed: tool.onPressed,
                        metrics: metrics,
                        palette: palette,
                      ),
                      SizedBox(width: metrics.gap * 0.75),
                    ],
                    if (showFullscreen && onFullscreen != null)
                      DockChip(
                        icon: Icons.fullscreen_rounded,
                        label: 'Fullscreen',
                        showLabel: false,
                        onPressed: onFullscreen!,
                        metrics: metrics,
                        palette: palette,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Speaker plus a short level bar — what anchors the play button so the
  /// left of the row reads as an instrument instead of a void.
  Widget _volume(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          volume <= 0.01
              ? Icons.volume_off_rounded
              : volume < 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          size: metrics.icon,
          color: palette.ink,
        ),
        SizedBox(
          width: metrics.target * 1.6,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: metrics.trackHeight * 0.75,
              activeTrackColor: palette.ink,
              inactiveTrackColor: palette.inactiveTrack,
              thumbColor: palette.ink,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: metrics.knob * 0.35,
              ),
              overlayShape: RoundSliderOverlayShape(
                overlayRadius: metrics.knob * 0.7,
              ),
            ),
            child: Slider(
              min: 0,
              max: 1,
              value: volume.clamp(0.0, 1.0),
              onChanged: onVolumeChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeReadout() {
    return ValueListenableBuilder<PlaybackUiClockValue>(
      valueListenable: clock,
      builder: (context, value, _) => Text(
        '${_fmt(value.position)}  /  ${_fmt(value.duration)}',
        maxLines: 1,
        style: TextStyle(
          color: palette.inkDim,
          fontSize: metrics.label,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// Centre zone. Carries the subtitle too — the design puts the stream's
  /// identity here, which is why the wide dock does not repeat the title in a
  /// top bar the way the narrow arrangements do.
  Widget _nowPlaying() {
    final hasSubtitle = subtitle?.isNotEmpty ?? false;
    if (title.isEmpty && !hasSubtitle) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.ink,
              fontSize: metrics.label * 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (hasSubtitle)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.inkDim, fontSize: metrics.label),
          ),
      ],
    );
  }

  List<Widget> _transport() {
    return [
      if (hasPrevious && onPrevious != null) ...[
        DockTransportButton(
          icon: Icons.skip_previous_rounded,
          label: 'Previous',
          onPressed: onPrevious!,
          metrics: metrics,
          palette: palette,
        ),
        SizedBox(width: metrics.gap * 1.5),
      ],
      DockTransportButton(
        icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        label: isPlaying ? 'Pause' : 'Play',
        onPressed: onPlayPause,
        primary: true,
        metrics: metrics,
        palette: palette,
      ),
      if (hasNext && onNext != null) ...[
        SizedBox(width: metrics.gap * 1.5),
        DockTransportButton(
          icon: Icons.skip_next_rounded,
          label: 'Next',
          onPressed: onNext!,
          metrics: metrics,
          palette: palette,
        ),
      ],
    ];
  }

  Widget _scrubber(BuildContext context, {bool bleed = false}) {
    return ValueListenableBuilder<PlaybackUiClockValue>(
      valueListenable: clock,
      builder: (context, value, _) => _scrubberRow(context, value, bleed),
    );
  }

  Widget _scrubberRow(
    BuildContext context,
    PlaybackUiClockValue value,
    bool bleed,
  ) {
    final total = value.duration.inMilliseconds <= 0
        ? 1
        : value.duration.inMilliseconds;
    final progress = (value.position.inMilliseconds / total).clamp(0.0, 1.0);

    final bar = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: metrics.trackHeight,
        // deep -> hot with a bloom at the played edge. Material's flat
        // activeTrackColor cannot express this.
        trackShape: GradientSliderTrackShape(
          deep: palette.deep,
          hot: palette.hot,
          inactive: palette.inactiveTrack,
          glow: palette.glow,
        ),
        thumbColor: palette.ink,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: metrics.knob / 2),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: metrics.knob * 0.8,
        ),
        overlayColor: palette.activeFill,
      ),
      child: Slider(
        min: 0,
        max: 1,
        value: progress,
        onChangeStart: (_) => onSeekBarChangedStart(),
        onChanged: onSeekBarChanged,
        onChangeEnd: (_) => onSeekBarChangeEnd(),
      ),
    );

    // Wide runs the bar edge to edge and moves the readouts into the left
    // zone; the narrower arrangements keep them flanking it.
    if (bleed) return SizedBox(height: metrics.target, child: bar);

    return SizedBox(
      height: DockLayoutInput.scrubberH,
      child: Row(
        children: [
          Flexible(
            child: Text(
              _fmt(value.position),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontSize: metrics.label,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(width: metrics.gap),
          Expanded(flex: 8, child: bar),
          SizedBox(width: metrics.gap),
          Flexible(
            child: Text(
              _fmt(value.duration),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontSize: metrics.label,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openOverflow(BuildContext context, List<_Tool> tools) {
    DockOverflowSheet.show(
      context,
      palette: palette,
      metrics: metrics,
      actions: [
        for (final tool in tools)
          DockOverflowAction(
            icon: tool.icon,
            label: tool.label,
            value: tool.value,
            active: tool.active,
            onPressed: tool.onPressed,
          ),
      ],
    );
  }
}
