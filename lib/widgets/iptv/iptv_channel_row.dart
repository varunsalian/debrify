import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_epg_service.dart';
import '../browse/brand_accent.dart';
import '../home/home_theme.dart';
import '../../utils/tv_keys.dart';

/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)".
final RegExp _resExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

const Color _liveDot = Color(0xFF34D399); // emerald — a calm "on air" cue

/// Row height for live channels (a square logo chip) and for on-demand items
/// (a 2:3 poster). The grid needs these to size its tiles, so they live here
/// next to the art they describe.
const double kIptvRowExtent = 74;
const double kIptvPosterRowExtent = 95;

/// Row height for live channels when the rows carry their own EPG block
/// (now-playing title, progress bar, up-next line) — the redesign's guide
/// look. Taller than [kIptvRowExtent] because the block is three lines.
const double kIptvEpgRowExtent = 100;

/// Compact guide-style list row for an IPTV channel: a small logo chip, the
/// channel name, and a "category • resolution" sub-line. Scales far better than
/// a logo grid for very large channel lists, and keeps the app's gold focus
/// language for DPAD.
class IptvChannelRow extends StatefulWidget {
  final IptvChannel channel;
  final bool isTelevision;
  final FocusNode? focusNode;
  final bool isFavorited;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFavoriteToggle;

  /// Fired when this row gains DPAD focus — drives the TV preview stage.
  final VoidCallback? onFocused;

  /// Opens this channel's programme schedule. TV fires it on RIGHT (the only
  /// key a row has left: OK plays, hold-OK favourites, LEFT is the sidebar's);
  /// touch/desktop get a small trailing calendar affordance instead. Null for
  /// channels without guide data — the key and the icon simply don't exist.
  final VoidCallback? onSchedule;

  /// Whether RIGHT triggers [onSchedule] on this row. Set by the list for
  /// rows on the grid's right edge only — the list knows the column count;
  /// the row doesn't. Rows with a genuine right-hand neighbour keep plain
  /// directional traversal (probing with focusInDirection instead was tried
  /// and jumps diagonally out of partial last rows). Touch/desktop ignore
  /// this — the calendar icon carries the action there.
  final bool scheduleOnRightKey;

  /// Saved playback position as a 0-1 fraction, or null when this item has
  /// none. Drawn as a bar across the foot of the poster.
  final double? progress;

  /// Draw 2:3 cover art instead of the square logo plate. Decided by the list
  /// rather than per-channel on purpose: the grid gives every tile one height
  /// ([kIptvPosterRowExtent] vs [kIptvRowExtent]), and a row that chose a
  /// poster inside a short tile would overflow.
  final bool poster;

  /// Show the channel's now/next EPG block inside the row (redesign). Decided
  /// by the list for the same reason as [poster]: the grid's tile height is
  /// all-or-nothing ([kIptvEpgRowExtent]). Rows whose channel has no guide
  /// data fall back to the classic "category • resolution" sub-line.
  final bool epg;

  const IptvChannelRow({
    super.key,
    required this.channel,
    required this.onTap,
    this.isTelevision = false,
    this.focusNode,
    this.isFavorited = false,
    this.onFavoriteToggle,
    this.onFocused,
    this.onSchedule,
    this.scheduleOnRightKey = false,
    this.progress,
    this.poster = false,
    this.epg = false,
  });

  @override
  State<IptvChannelRow> createState() => _IptvChannelRowState();
}

class _IptvChannelRowState extends State<IptvChannelRow>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  /// Touch phones/tablets have no hover, so the favourite affordance can't hide
  /// behind one — keep it visible there. Desktop reveals it on hover, TV on
  /// focus; Android TV reports as android but is flagged via [isTelevision].
  bool get _isTouchMobile =>
      !widget.isTelevision &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // Long-press OK on TV toggles favorite; a short press still plays. The hold
  // is driven by a controller so the focused row can show a filling heart —
  // making the otherwise-invisible gesture discoverable.
  static const _favHoldDuration = Duration(milliseconds: 500);
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _favHoldDuration,
  );
  bool _favHoldFired = false;

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _favHoldFired = true;
        widget.onFavoriteToggle?.call(!widget.isFavorited);
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isLive = ch.isLive;
    final brand = brandAccentFor(ch.name);

    // Pull the resolution out of the name into the sub-line; show a clean name.
    final resMatch = _resExp.firstMatch(ch.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? ch.name
        : ch.name
            .replaceRange(resMatch.start, resMatch.end, '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    final group = ch.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];
    final sub = subParts.isNotEmpty
        ? subParts.join('  •  ')
        : (isLive ? 'Live' : '');

    final fx = widget.isTelevision
        ? Duration.zero
        : const Duration(milliseconds: 150);

    final row = AnimatedContainer(
      duration: fx,
      // Constant 2px border (transparent at rest) so focus never shifts layout.
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _active ? const Color(0xFF141824) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _active ? HomeTheme.focusGold : Colors.transparent,
          width: 2,
        ),
        boxShadow: _active
            ? [
                BoxShadow(
                  color: HomeTheme.focusGold.withValues(alpha: 0.28),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          _LogoChip(
            logoUrl: ch.logoUrl,
            name: displayName,
            brand: brand,
            // On-demand lists get posters: Xtream serves real cover art in
            // `stream_icon` for VOD, and squeezing it into the live-channel
            // logo square made it unreadable.
            poster: widget.poster,
            progress: widget.progress,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isLive) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _liveDot,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _liveDot.withValues(alpha: 0.6),
                              blurRadius: 7,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: _active ? 1.0 : 0.94,
                          ),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.epg)
                  // The EPG block owns the space under the name. It renders
                  // the classic sub-line itself while it has nothing better —
                  // so a channel without guide data looks exactly like before,
                  // just with more air.
                  _RowEpg(channel: ch, fallback: sub)
                else if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildScheduleTrailing(),
          _buildFavTrailing(),
        ],
      ),
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          widget.onFocused?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: widget.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        // RIGHT opens the schedule on right-edge rows (the list decides
        // which those are — see [scheduleOnRightKey]). Key-down only;
        // repeats are swallowed so holding RIGHT can't re-open it.
        if (widget.isTelevision &&
            widget.scheduleOnRightKey &&
            widget.onSchedule != null &&
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (event is KeyDownEvent) widget.onSchedule!();
          return KeyEventResult.handled;
        }

        final isSelect = isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space;
        if (!isSelect) return KeyEventResult.ignored;

        // Without a favorite action (or off-TV), keep press-to-play.
        final canHoldToFavorite =
            widget.isTelevision && widget.onFavoriteToggle != null;
        if (!canHoldToFavorite) {
          if (event is KeyDownEvent) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (event is KeyDownEvent) {
          _favHoldFired = false;
          _holdController.forward(from: 0); // fills the heart over 500ms
          return KeyEventResult.handled;
        }
        if (event is KeyUpEvent) {
          // Released before the fill completed → treat as a tap (play).
          if (!_favHoldFired) widget.onTap();
          _holdController.reset();
          _favHoldFired = false;
          return KeyEventResult.handled;
        }
        // Swallow auto-repeat while the key is held.
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovered = true);
          // Pointer platforms: hovering IS the "focus" that drives the
          // two-pane preview stage (the stage's own dwell debounces
          // fly-overs). TV never mouses, so the guard is just clarity.
          if (!widget.isTelevision) widget.onFocused?.call();
        },
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: row,
        ),
      ),
    );
  }

  /// Trailing schedule affordance for touch/desktop (TV opens the schedule
  /// with RIGHT instead — no icon there). Follows the favourite heart's
  /// visibility rules: always present on touch, hover-revealed on desktop.
  Widget _buildScheduleTrailing() {
    if (widget.onSchedule == null || widget.isTelevision) {
      return const SizedBox.shrink();
    }
    final show = _active || _isTouchMobile;
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton(
        onPressed: widget.onSchedule,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        tooltip: 'TV guide',
        icon: Icon(
          Icons.calendar_view_day_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  /// Trailing favourite affordance, per input model:
  /// - TV: a non-focusable hint on the focused row ("HOLD OK" + a heart that
  ///   fills as OK is held); a small filled heart on favourited rows otherwise.
  /// - Desktop/mobile: a tappable heart, revealed on hover / when favourited /
  ///   always on touch (no hover there).
  Widget _buildFavTrailing() {
    if (widget.onFavoriteToggle == null) return const SizedBox.shrink();

    if (widget.isTelevision) {
      if (_focused) {
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: AnimatedBuilder(
            animation: _holdController,
            builder: (_, __) => _FavHint(
              favorited: widget.isFavorited,
              progress: _holdController.value,
            ),
          ),
        );
      }
      if (widget.isFavorited) {
        return const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.favorite_rounded,
              size: 18, color: Color(0xFFF43F5E)),
        );
      }
      return const SizedBox.shrink();
    }

    final show = widget.isFavorited || _active || _isTouchMobile;
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: _FavButton(
        favorited: widget.isFavorited,
        onTap: () => widget.onFavoriteToggle!(!widget.isFavorited),
      ),
    );
  }
}

/// The in-row now/next block (redesign): what's airing right now, how far in
/// it is, and what's up next — the guide readable without focusing anything.
///
/// Follows [IptvRailEpgCard]'s fetch discipline exactly: paint synchronously
/// from the service cache when possible; otherwise fetch only after the row
/// has been mounted a beat (scrolling a big list must not fire a request per
/// fly-by row — the service additionally throttles and coalesces). A slow
/// ticker advances the progress bar and rolls past programme boundaries; the
/// service cache is the staleness oracle (a null peek means "time to re-ask").
class _RowEpg extends StatefulWidget {
  final IptvChannel channel;

  /// The classic "category • resolution" sub-line, shown while there is no
  /// guide data (not capable, still loading, or the guide has a gap).
  final String fallback;

  const _RowEpg({required this.channel, required this.fallback});

  @override
  State<_RowEpg> createState() => _RowEpgState();
}

class _RowEpgState extends State<_RowEpg> {
  EpgNowNext? _data;
  String? _forUrl;
  Timer? _fetchDebounce;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
    // An XMLTV guide finishing its first download changes what every built
    // row can show (only built rows listen — the grid recycles the rest).
    IptvEpgService.instance.contextVersion.addListener(_onEpgContextChanged);
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final ch = widget.channel;
      if (!IptvEpgService.isEpgCapable(ch)) return;
      final cached = IptvEpgService.instance.peekNowNext(ch.url);
      if (cached == null) {
        // Cache invalidated itself (programme ended / retry window passed).
        _scheduleFetch();
      } else if (!identical(cached, _data)) {
        setState(() => _data = cached);
      } else if (cached.now != null) {
        setState(() {}); // repaint the progress bar
      }
    });
  }

  @override
  void didUpdateWidget(_RowEpg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.url != widget.channel.url) _sync();
  }

  @override
  void dispose() {
    IptvEpgService.instance.contextVersion.removeListener(_onEpgContextChanged);
    _fetchDebounce?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _onEpgContextChanged() {
    if (mounted) _sync();
  }

  void _sync() {
    _fetchDebounce?.cancel();
    final ch = widget.channel;
    _forUrl = ch.url;
    if (!IptvEpgService.isEpgCapable(ch)) {
      if (_data != null) setState(() => _data = null);
      return;
    }
    final cached = IptvEpgService.instance.peekNowNext(ch.url);
    if (cached != null) {
      setState(() => _data = cached);
      return;
    }
    if (_data != null) setState(() => _data = null);
    _scheduleFetch();
  }

  void _scheduleFetch() {
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 350), _fetch);
  }

  Future<void> _fetch() async {
    final url = _forUrl;
    if (url == null) return;
    final result = await IptvEpgService.instance.nowNext(url);
    if (!mounted || url != _forUrl) return;
    if (!result.isEmpty) setState(() => _data = result);
  }

  @override
  Widget build(BuildContext context) {
    final now = _data?.now;
    final next = _data?.next;
    if (now == null && next == null) {
      // No guide data (yet): the classic sub-line keeps the row honest.
      if (widget.fallback.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          widget.fallback,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    final at = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (now != null) ...[
          const SizedBox(height: 3),
          Text(
            now.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          // Same bar the rail card draws, at row scale.
          ClipRRect(
            borderRadius: BorderRadius.circular(1.5),
            child: SizedBox(
              height: 3,
              child: Row(
                children: [
                  Expanded(
                    flex: (now.progressAt(at) * 1000).round().clamp(0, 1000),
                    child: const ColoredBox(color: HomeTheme.focusGold),
                  ),
                  Expanded(
                    flex: 1000 -
                        (now.progressAt(at) * 1000).round().clamp(0, 1000),
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (next != null) ...[
          const SizedBox(height: 4),
          Text(
            '${TimeOfDay.fromDateTime(next.start).format(context)}'
            '  ·  ${next.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// TV favourite hint: an "HOLD OK" prompt plus a heart that fills over the hold
/// (a ring sweeps and the heart tints toward its favourited state), so the
/// hold-to-favourite gesture is visible rather than hidden.
class _FavHint extends StatelessWidget {
  final bool favorited;
  final double progress; // 0..1 hold progress
  const _FavHint({required this.favorited, required this.progress});

  @override
  Widget build(BuildContext context) {
    final holding = progress > 0.02 && progress < 1.0;
    final done = favorited || progress >= 1.0;
    final heartColor = done
        ? const Color(0xFFF43F5E)
        : Color.lerp(
            Colors.white.withValues(alpha: 0.7),
            const Color(0xFFF43F5E),
            progress,
          )!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The prompt yields to the ring once the user starts holding.
        if (!holding)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              'HOLD OK',
              style: TextStyle(
                color: HomeTheme.focusGold.withValues(alpha: 0.95),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (progress > 0.02)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    color: HomeTheme.focusGold,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              Icon(
                done
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 16,
                color: heartColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small rounded artwork chip with a brand-tinted plate and a graceful
/// fallback. Live channels get a square logo plate (letterboxed, since station
/// logos are wide and must not be cropped); on-demand items get a 2:3 poster
/// filling the frame, optionally with a resume bar across its foot.
class _LogoChip extends StatelessWidget {
  final String? logoUrl;
  final String name;
  final Color brand;
  final bool poster;
  final double? progress;
  const _LogoChip({
    required this.logoUrl,
    required this.name,
    required this.brand,
    this.poster = false,
    this.progress,
  });

  static const double _logoSize = 50;
  static const double _posterWidth = 46;
  static const double _posterHeight = 69; // 2:3

  @override
  Widget build(BuildContext context) {
    final hasArt = logoUrl != null && logoUrl!.isNotEmpty;
    return Container(
      width: poster ? _posterWidth : _logoSize,
      height: poster ? _posterHeight : _logoSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(poster ? 7 : 11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(brand.withValues(alpha: 0.16),
                const Color(0xFF1E2030)),
            const Color(0xFF14141D),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            // A poster is the art — it fills its frame. A logo is a mark on a
            // plate and needs the breathing room.
            padding: EdgeInsets.all(poster ? 0 : 7),
            child: hasArt
                ? CachedNetworkImage(
                    imageUrl: logoUrl!,
                    fit: poster ? BoxFit.cover : BoxFit.contain,
                    // IPTV art is often 1000px+ going into a tiny slot —
                    // uncapped decodes janked scrolling and thrashed the TV's
                    // small image cache (re-decoding on every scroll-back).
                    memCacheHeight: poster ? 200 : 96,
                    placeholder: (_, __) => _fallback(),
                    errorWidget: (_, __, ___) => _fallback(),
                  )
                : _fallback(),
          ),
          if (poster && progress != null && progress! > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ResumeBar(progress: progress!.clamp(0.0, 1.0)),
            ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Center(
      child: Icon(
        poster ? Icons.movie_rounded : Icons.live_tv_rounded,
        size: 22,
        color: brand.withValues(alpha: 0.85),
      ),
    );
  }
}

/// How far into an on-demand item the viewer got, drawn across the foot of its
/// poster. Sits on a scrim so it reads over bright artwork.
class _ResumeBar extends StatelessWidget {
  final double progress;
  const _ResumeBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      color: Colors.black.withValues(alpha: 0.55),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(color: HomeTheme.focusGold),
      ),
    );
  }
}

class _FavButton extends StatelessWidget {
  final bool favorited;
  final VoidCallback onTap;
  const _FavButton({required this.favorited, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            favorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
            color: favorited
                ? const Color(0xFFF43F5E)
                : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
