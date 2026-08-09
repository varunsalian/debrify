import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../models/gesture_state.dart';
import '../services/playback_ui_clock.dart';

/// The television transport bar for the Flutter player.
///
/// Separate from [Controls] on purpose. That widget is built for thumbs — no
/// focus nodes, no focus affordance, touch-sized gesture targets — and Android
/// TV never revealed the gap because it hands playback to the native player
/// instead. Rather than make one widget serve two contradictory input models,
/// televisions get this bar and the touch path stays byte-for-byte unchanged.
///
/// The contract mirrors the native Android TV player so users moving between
/// the two find the same behaviour; the screen owns the keys and the focus
/// nodes, this widget owns the pixels.
class TvControls extends StatefulWidget {
  const TvControls({
    super.key,
    required this.title,
    required this.subtitle,
    required this.clock,
    required this.isPlaying,
    required this.isLive,
    required this.isTransitioning,
    required this.scopeNode,
    required this.playPauseFocusNode,
    required this.progressFocusNode,
    required this.progressFocusable,
    required this.onPlayPause,
    required this.onShowTracks,
    required this.onSpeed,
    required this.onAspect,
    required this.onSleepTimer,
    required this.speed,
    required this.aspectMode,
    this.hideOptions = false,
    this.scrubPreview,
    this.sleepTimerLabel,
    this.onNext,
    this.onPrevious,
    this.onShowPlaylist,
    this.onShowSources,
    this.onShowGuide,
    this.onShowIptvChannels,
    this.onNextChannel,
    this.onPreviousChannel,
    this.hasRecord = false,
    this.isRecording = false,
    this.onRecord,
    this.infoPanel,
    this.onInteract,
  });

  /// Fired whenever the user actually works the dock — pressing OK on a
  /// control, or tapping one. The host uses it to restart the auto-hide
  /// countdown: the dock claims OK itself, so those presses never reach the
  /// screen's key handler and would otherwise let the bar vanish under the
  /// user's hands a moment after they pressed something.
  final VoidCallback? onInteract;

  final String title;
  final String? subtitle;
  final ValueListenable<PlaybackUiClockValue> clock;
  final bool isPlaying;

  /// Live streams have nothing to seek and no meaningful speed, so the bar
  /// drops progress and speed and swaps prev/next for channel zapping — the
  /// same shape the native player's live dock takes.
  final bool isLive;

  /// A source switch or IPTV zap is in flight. The bar stays on screen but
  /// every action is inert: acting now would seek or advance the OUTGOING item.
  final bool isTransitioning;

  /// Owned by the screen so it can raise the bar, restore focus and decide
  /// whether auto-hide is allowed (it never hides while focus is in here).
  final FocusScopeNode scopeNode;
  final FocusNode playPauseFocusNode;
  final FocusNode progressFocusNode;

  /// False when duration is unknown or the stream is live: traversal skips the
  /// progress row entirely rather than parking focus on a dead control.
  final bool progressFocusable;

  /// Non-null while a cinema scrub is in flight — the position the user is
  /// aiming at, which the fill and readout follow until OK confirms.
  final Duration? scrubPreview;

  final VoidCallback onPlayPause;
  final VoidCallback onShowTracks;
  final VoidCallback onSpeed;
  final VoidCallback onAspect;
  final VoidCallback onSleepTimer;
  final String? sleepTimerLabel;
  final double speed;
  final AspectMode aspectMode;

  /// Callers that want a bare transport (Magic TV, some IPTV surfaces) hide the
  /// options cluster; the touch dock already honours this.
  final bool hideOptions;

  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onShowPlaylist;
  final VoidCallback? onShowSources;
  final VoidCallback? onShowGuide;
  final VoidCallback? onShowIptvChannels;
  final VoidCallback? onNextChannel;
  final VoidCallback? onPreviousChannel;
  final bool hasRecord;
  final bool isRecording;
  final VoidCallback? onRecord;

  /// Live IPTV glues its channel/now-next panel to the top edge so the two
  /// read as one surface, exactly as the touch dock does.
  final Widget? infoPanel;

  @override
  State<TvControls> createState() => _TvControlsState();
}

class _TvControlsState extends State<TvControls> {
  /// The label of whatever is focused. Rendered once, centred under the
  /// transport row, instead of a caption per button: the bar stays clean and
  /// still always says what you are on.
  String? _focusedLabel;

  void _setLabel(String label, bool focused) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // Mid-build: defer rather than markNeedsBuild during build.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _setLabel(label, focused),
      );
      return;
    }
    if (focused) {
      if (_focusedLabel != label) setState(() => _focusedLabel = label);
    } else if (_focusedLabel == label) {
      setState(() => _focusedLabel = null);
    }
  }

  /// Release names ("Interstellar (2014) (2014) 1080p BrRip x264 - YIFY") are
  /// what the file is called, not what the film is called. A 10-foot bar shows
  /// the latter: cut at the first quality/codec/group token and collapse the
  /// year that then repeats.
  static final RegExp _releaseNoise = RegExp(
    r'\b(\d{3,4}p|4k|uhd|bluray|blu-ray|brrip|bdrip|webrip|web-dl|webdl|hdrip|'
    r'dvdrip|remux|x264|x265|h264|h265|hevc|avc|aac|ac3|eac3|dts|ddp?5|'
    r'yify|yts|rarbg|proper|repack|extended|imax)\b',
    caseSensitive: false,
  );

  static String _cleanTitle(String raw) {
    var text = raw.replaceAll('.', ' ').replaceAll('_', ' ');
    final cut = _releaseNoise.firstMatch(text);
    if (cut != null) text = text.substring(0, cut.start);
    text = text.replaceAll(RegExp(r'[\s\-–—\[\](){}]+$'), '').trim();
    // "Interstellar (2014) (2014)" -> "Interstellar (2014)"
    text = text.replaceAllMapped(
      RegExp(r'\((\d{4})\)\s*\(\1\)'),
      (m) => '(${m[1]})',
    );
    return text.isEmpty ? raw : text;
  }

  static String _fmt(Duration d) {
    final neg = d.isNegative;
    final v = neg ? -d : d;
    final h = v.inHours;
    final m = v.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = v.inSeconds.remainder(60).toString().padLeft(2, '0');
    final body = h > 0 ? '$h:$m:$s' : '$m:$s';
    return neg ? '-$body' : body;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // Exactly the host's timeline rule: live, an unknown duration, or a
    // session that asked for no seekbar at all (Magic/Debrify TV) each mean
    // there is no timeline to draw. Drawing one and merely refusing focus
    // showed a scrubber the session had explicitly turned off.
    final showProgress = widget.progressFocusable;

    return FocusScope(
      node: widget.scopeNode,
      // The slot this occupies is the full player area, so the bar has to
      // anchor itself; a bare Column would float mid-screen.
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          // A real scrim. The bar is only as tall as its content, so without
          // generous top padding inside the gradient the title lands on bright
          // video and the whole thing reads as unfinished.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x00000000),
                Color(0x66000000),
                Color(0xD9000000),
                Color(0xF2000000),
              ],
              stops: [0.0, 0.28, 0.62, 1.0],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(56, 52, 56, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.infoPanel != null) widget.infoPanel!,
              _identityRow(),
              if (showProgress) ...[
                const SizedBox(height: 6),
                ValueListenableBuilder<PlaybackUiClockValue>(
                  valueListenable: widget.clock,
                  builder: (context, value, _) => _TvProgressRow(
                    focusNode: widget.progressFocusNode,
                    focusable: widget.progressFocusable,
                    position: value.position,
                    duration: value.duration,
                    preview: widget.scrubPreview,
                    accent: accent,
                    format: _fmt,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _transportRow(),
              // Fixed height so the row never jumps as the label appears.
              // Reserved height so the row never shifts as the label fades in.
              SizedBox(
                height: 14,
                child: AnimatedOpacity(
                  opacity: _focusedLabel == null ? 0 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Text(
                    _focusedLabel ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identityRow() {
    final subtitle = widget.subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.title.isNotEmpty)
                Text(
                  _cleanTitle(widget.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.sleepTimerLabel != null)
          Container(
            margin: const EdgeInsets.only(left: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bedtime_rounded,
                  size: 13,
                  color: Colors.white70,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.sleepTimerLabel!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _transportRow() {
    final inert = widget.isTransitioning;
    final transport = <Widget>[];
    final options = <Widget>[];

    void add(
      IconData icon,
      String label,
      VoidCallback? onPressed, {
      bool primary = false,
      FocusNode? node,
      bool active = false,
      bool option = false,
    }) {
      if (onPressed == null) return; // omitted, never disabled-and-focusable
      (option ? options : transport).add(
        _TvIconButton(
          icon: icon,
          label: label,
          primary: primary,
          active: active,
          focusNode: node,
          onPressed: inert ? null : onPressed,
          onFocusLabel: _setLabel,
          onInteract: widget.onInteract,
        ),
      );
    }

    if (widget.isLive) {
      // Live dock order follows the native player: identity/tracks first, the
      // channel pair around play/pause, then the live-only tools.
      add(
        Icons.skip_previous_rounded,
        'Channel −',
        widget.onPreviousChannel ?? widget.onPrevious,
      );
      add(
        widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        widget.isPlaying ? 'Pause' : 'Play',
        widget.onPlayPause,
        primary: true,
        node: widget.playPauseFocusNode,
      );
      add(
        Icons.skip_next_rounded,
        'Channel +',
        widget.onNextChannel ?? widget.onNext,
      );
      add(
        Icons.subtitles_rounded,
        'Subtitles & Audio',
        widget.onShowTracks,
        option: true,
      );
      add(
        Icons.grid_view_rounded,
        'Guide',
        widget.onShowGuide ?? widget.onShowIptvChannels,
        option: true,
      );
      add(Icons.dns_rounded, 'Sources', widget.onShowSources, option: true);
      add(
        Icons.aspect_ratio_rounded,
        _aspectLabel(),
        widget.onAspect,
        option: true,
      );
      if (widget.hasRecord) {
        add(
          widget.isRecording
              ? Icons.stop_circle_rounded
              : Icons.fiber_manual_record_rounded,
          widget.isRecording ? 'Stop recording' : 'Record',
          widget.onRecord,
          active: widget.isRecording,
          option: true,
        );
      }
      add(
        Icons.bedtime_rounded,
        'Sleep timer',
        widget.onSleepTimer,
        option: true,
      );
    } else {
      add(Icons.skip_previous_rounded, 'Previous', widget.onPrevious);
      add(Icons.replay_10_rounded, 'Back 10s', () => _nudge(-10));
      add(
        widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        widget.isPlaying ? 'Pause' : 'Play',
        widget.onPlayPause,
        primary: true,
        node: widget.playPauseFocusNode,
      );
      add(Icons.forward_10_rounded, 'Forward 10s', () => _nudge(10));
      add(Icons.skip_next_rounded, 'Next', widget.onNext);
      add(
        Icons.subtitles_rounded,
        'Subtitles & Audio',
        widget.onShowTracks,
        option: true,
      );
      add(
        Icons.playlist_play_rounded,
        'Episodes',
        widget.onShowPlaylist,
        option: true,
      );
      add(Icons.dns_rounded, 'Sources', widget.onShowSources, option: true);
      add(
        Icons.speed_rounded,
        '${widget.speed}x speed',
        widget.onSpeed,
        option: true,
      );
      add(
        Icons.aspect_ratio_rounded,
        _aspectLabel(),
        widget.onAspect,
        option: true,
      );
      add(
        Icons.bedtime_rounded,
        'Sleep timer',
        widget.onSleepTimer,
        option: true,
      );
    }

    // Transport on the left, options on the right — the layout every OTT player
    // uses. A single centred row of identical circles is what made this read as
    // a prototype: nothing told the eye what was primary.
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Row(
        children: [
          for (int i = 0; i < transport.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            transport[i],
          ],
          const Spacer(),
          if (!widget.hideOptions)
            for (int i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              options[i],
            ],
        ],
      ),
    );
  }

  /// Same wording the touch bar uses, so the two never disagree about what a
  /// mode is called.
  String _aspectLabel() => switch (widget.aspectMode) {
    AspectMode.contain => 'Contain',
    AspectMode.cover => 'Cover',
    AspectMode.fitWidth => 'Fit Width',
    AspectMode.fitHeight => 'Fit Height',
    AspectMode.aspect16_9 => '16:9',
    AspectMode.aspect4_3 => '4:3',
    AspectMode.aspect21_9 => '21:9',
    AspectMode.aspect1_1 => '1:1',
    AspectMode.aspect3_2 => '3:2',
    AspectMode.aspect5_4 => '5:4',
  };

  /// The ±10 buttons exist for discoverability; the remote's LEFT/RIGHT does
  /// the same thing without raising the bar. Routed through the screen's seek
  /// so trackers and resume see one seek, not two.
  void _nudge(int seconds) {
    final value = widget.clock.value;
    final target = value.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > value.duration ? value.duration : target);
    _TvControlsSeek.of(context)?.call(clamped);
  }
}

/// Lets the ±10 buttons reach the screen's seek without threading another
/// callback through every constructor call.
class _TvControlsSeek extends InheritedWidget {
  const _TvControlsSeek({required this.seek, required super.child});

  final ValueChanged<Duration> seek;

  static ValueChanged<Duration>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TvControlsSeek>()?.seek;

  @override
  bool updateShouldNotify(_TvControlsSeek oldWidget) => seek != oldWidget.seek;
}

/// Wraps [TvControls] with the seek callback its ±10 buttons need.
class TvControlsScope extends StatelessWidget {
  const TvControlsScope({super.key, required this.seek, required this.child});

  final ValueChanged<Duration> seek;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _TvControlsSeek(seek: seek, child: child);
}

/// A focusable transport button.
///
/// The focus affordance is the whole point of a 10-foot bar: at three metres a
/// subtle tint is invisible, so focus scales the button, fills it solid,
/// inverts the icon and lights a ring plus an outer glow.
class _TvIconButton extends StatefulWidget {
  const _TvIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.onFocusLabel,
    this.onInteract,
    this.focusNode,
    this.primary = false,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final void Function(String label, bool focused) onFocusLabel;
  final VoidCallback? onInteract;
  final FocusNode? focusNode;
  final bool primary;
  final bool active;

  @override
  State<_TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<_TvIconButton> {
  bool _focused = false;

  @override
  void didUpdateWidget(covariant _TvIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Record -> Stop recording flips while the control keeps focus, so the
    // caption has to be re-pushed; it is only sent on focus transitions.
    if (_focused && widget.label != oldWidget.label) {
      // Deferred: this runs while the parent is building us, and the callback
      // setStates the parent.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focused) widget.onFocusLabel(widget.label, true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.primary ? 44.0 : 36.0;
    final accent = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: widget.onPressed != null,
        skipTraversal: widget.onPressed == null,
        // The focused widget sees keys first, so OK is claimed here rather
        // than by the screen's handler. `enter` is what the Siri Remote's
        // click pad sends; the rest cover Android TV remotes, controllers and
        // keyboards.
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final k = event.logicalKey;
          final activates =
              k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter ||
              k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.gameButtonA ||
              k == LogicalKeyboardKey.space;
          if (!activates || widget.onPressed == null) {
            return KeyEventResult.ignored;
          }
          widget.onInteract?.call();
          widget.onPressed!();
          return KeyEventResult.handled;
        },
        onFocusChange: (f) {
          setState(() => _focused = f);
          widget.onFocusLabel(widget.label, f);
        },
        child: GestureDetector(
          onTap: widget.onPressed == null
              ? null
              : () {
                  widget.onInteract?.call();
                  widget.onPressed!();
                },
          child: AnimatedScale(
            scale: _focused ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _focused
                    ? Colors.white
                    : Colors.white.withValues(
                        alpha: widget.primary ? 0.20 : 0.12,
                      ),
                border: _focused
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.28),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                size: widget.primary ? 24 : 18,
                color: _focused
                    ? const Color(0xFF0B0B0F)
                    : (widget.active
                          ? accent
                          : Colors.white.withValues(alpha: 0.92)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The progress row. Focusable only when there is something to seek; while a
/// cinema scrub is in flight the fill and the readout follow the preview so the
/// user sees where they are aiming before committing.
class _TvProgressRow extends StatefulWidget {
  const _TvProgressRow({
    required this.focusNode,
    required this.focusable,
    required this.position,
    required this.duration,
    required this.preview,
    required this.accent,
    required this.format,
  });

  final FocusNode focusNode;
  final bool focusable;
  final Duration position;
  final Duration duration;
  final Duration? preview;
  final Color accent;
  final String Function(Duration) format;

  @override
  State<_TvProgressRow> createState() => _TvProgressRowState();
}

class _TvProgressRowState extends State<_TvProgressRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final shown = widget.preview ?? widget.position;
    final total = widget.duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (shown.inMilliseconds / total).clamp(0.0, 1.0);
    final scrubbing = widget.preview != null;
    final live = _focused || scrubbing;
    final delta = scrubbing ? widget.preview! - widget.position : Duration.zero;

    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.focusable,
      skipTraversal: !widget.focusable,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scrubbing)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  '${widget.format(shown)}   ·   '
                  '${delta.isNegative ? '−' : '+'}${widget.format(delta.abs())}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: live ? 6 : 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: live ? 6 : 3,
                      width: w * fraction,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    if (live)
                      Positioned(
                        left: (w * fraction - 6).clamp(0.0, w - 12),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: widget.accent.withValues(alpha: 0.6),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.format(shown),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '-${widget.format(widget.duration - shown)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
