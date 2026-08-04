import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/iptv_epg_service.dart';
import '../browse/brand_accent.dart';
import '../home/home_theme.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';

/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)".
final RegExp _resExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

const Color _liveDot = Color(0xFF34D399); // emerald — a calm "on air" cue

/// Row heights for live channels (a square logo chip) and on-demand items
/// (a 2:3 poster). Narrow live rows get a little more height so a wrapped
/// channel name and its category can coexist without clipping. The grid needs
/// these to size its tiles, so they live here next to the art they describe.
const double kIptvRowExtent = 74;
const double kIptvNarrowRowExtent = 84;
const double kIptvPosterRowExtent = 95;

/// Cockpit rows (rail + stage eat width): the two-line name needs the extra
/// height these carry over their single-line bases.
const double kIptvRowTallExtent = 92;
const double kIptvEpgRowTallExtent = 118;

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
  final bool isPreviewSelected;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFavoriteToggle;

  /// Whether this channel is in any list at all (including Favorites) —
  /// drives the small "saved somewhere" marker.
  final bool inAnyList;

  /// Opens the "add to list" picker — the dialog offers Favorites and a
  /// "Create new list" row, so it is useful even before the user has made a
  /// list of their own. Null for rows that can't be saved at all (series).
  final VoidCallback? onOpenListPicker;

  /// Whether the user has lists beyond the built-in Favorites.
  ///
  /// Only the TV hold gesture consults this: with no lists of their own, HOLD
  /// OK stays a direct favorite toggle rather than growing a dialog nobody
  /// asked for. The pointer heart always opens the picker — a tap is cheap
  /// and reversible, a held remote button is neither.
  final bool hasCustomLists;

  /// Fired when this row gains DPAD focus — drives the TV preview stage.
  final VoidCallback? onFocused;

  /// Fired when a POINTER has rested on this row long enough to read as
  /// intent — the desktop counterpart of [onFocused], and deliberately a
  /// separate signal: the stage suppresses focus-driven retargets while the
  /// cursor is inside it, and must never suppress this one.
  final VoidCallback? onPointerRest;

  /// Fired from dispose — tells the list this row no longer holds its cached
  /// focus node. This is the ONLY reliable detachment signal: FocusNode.context
  /// is assigned on attach and never reverts to null on detach, so the list
  /// cannot infer "row gone" from the node itself, and retiring nodes on any
  /// other evidence either leaks them (per row ever scrolled — the big-catalog
  /// OOM) or disposes one still in use.
  final VoidCallback? onDetached;

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

  /// Cockpit rows: the center column is narrower (rail + stage), so channel
  /// names get a second line instead of aggressive truncation. Pair with the
  /// tall row extents.
  final bool twoLineName;

  const IptvChannelRow({
    super.key,
    required this.channel,
    required this.onTap,
    this.isTelevision = false,
    this.focusNode,
    this.isFavorited = false,
    this.isPreviewSelected = false,
    this.onFavoriteToggle,
    this.inAnyList = false,
    this.onOpenListPicker,
    this.hasCustomLists = false,
    this.onFocused,
    this.onPointerRest,
    this.onDetached,
    this.onSchedule,
    this.scheduleOnRightKey = false,
    this.progress,
    this.poster = false,
    this.epg = false,
    this.twoLineName = false,
  });

  @override
  State<IptvChannelRow> createState() => _IptvChannelRowState();
}

class _IptvChannelRowState extends State<IptvChannelRow>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered || widget.isPreviewSelected;
  bool get _tabletPreviewActive =>
      widget.isPreviewSelected && !_focused && !_hovered;
  Color get _activeAccent =>
      _tabletPreviewActive ? HomeTheme.chromeAccent : HomeTheme.focusGold;

  /// Touch phones/tablets have no hover, so the favourite affordance can't hide
  /// behind one — keep it visible there. Desktop reveals it on hover, TV on
  /// focus; Android TV reports as android but is flagged via [isTelevision].
  bool get _isTouchMobile =>
      !widget.isTelevision &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // Long-press OK on TV toggles favorite — or opens the list picker once the
  // user has lists of their own; a short press still plays. The hold is
  // driven by a controller so the focused row can show a filling heart,
  // making the otherwise-invisible gesture discoverable.
  static const _favHoldDuration = Duration(milliseconds: 500);

  /// How long a pointer must REST on a row before it retargets the preview
  /// stage. A sweep crosses a row in ~30-80ms, so anything past ~150ms already
  /// stops the stage being stolen in transit; the rest of this budget covers
  /// HESITATION — pausing mid-journey without meaning to select. Raising it
  /// further buys diminishing margin against a slower pause and charges every
  /// deliberate hover for it, so if this still isn't enough the answer is a
  /// direction guard (ignore rows while the pointer travels toward the stage),
  /// not a bigger number.
  static const _hoverIntentDelay = Duration(milliseconds: 400);

  /// Armed on hover, cancelled the moment the pointer leaves — see the comment
  /// at its arming site for why hovering can't retarget the stage on contact.
  Timer? _hoverIntent;
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _favHoldDuration,
  );
  bool _favHoldFired = false;

  /// Whether this row received the OK/select KEY-DOWN that a key-up belongs
  /// to. The favoritable path plays on key-UP (to tell a quick press from a
  /// hold), so without this a key-up that lands here after focus moved
  /// mid-press — e.g. selecting a source collapses the rail onto this row
  /// while OK is still held — would read as a tap and auto-play a channel
  /// the user never pressed.
  bool _sawSelectDown = false;

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _favHoldFired = true;
        final openPicker = widget.onOpenListPicker;
        if (openPicker != null && widget.hasCustomLists) {
          openPicker();
        } else {
          widget.onFavoriteToggle?.call(!widget.isFavorited);
        }
      }
    });
  }

  @override
  void dispose() {
    _hoverIntent?.cancel();
    _holdController.dispose();
    widget.onDetached?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isLive = ch.isLive;
    final brand = brandAccentFor(ch.name);
    final isNarrow =
        !widget.isTelevision && MediaQuery.sizeOf(context).width < 600;

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
        color: _active
            ? (_tabletPreviewActive
                  ? const Color(0xFF17132E)
                  : const Color(0xFF141824))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _active ? _activeAccent : Colors.transparent,
          width: 2,
        ),
        boxShadow: _active
            ? [
                BoxShadow(
                  color: _activeAccent.withValues(alpha: 0.28),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          if (isLive && ch.channelNumber != null) ...[
            SizedBox(
              width: 45,
              child: Text(
                ch.channelNumber.toString(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: _active
                      ? _activeAccent
                      : Colors.white.withValues(alpha: 0.42),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
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
                        // Phone-width rows have enough height for a second
                        // title line, and cockpit rows opt in explicitly
                        // (their column is narrow; the tall extents carry the
                        // room). Elsewhere one line keeps the denser rhythm.
                        maxLines: (isNarrow || widget.twoLineName) ? 2 : 1,
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
        if (!f) {
          // Focus left mid-press — disarm so a later stray key-up can't play.
          _sawSelectDown = false;
          _favHoldFired = false;
          _holdController.reset();
        }
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

        final isSelect =
            isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space;
        if (!isSelect) return KeyEventResult.ignored;

        // Without a favorite action or a list picker (or off-TV), keep
        // press-to-play.
        final canHoldToFavorite =
            widget.isTelevision &&
            (widget.onFavoriteToggle != null ||
                widget.onOpenListPicker != null);
        if (!canHoldToFavorite) {
          if (event is KeyDownEvent) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (event is KeyDownEvent) {
          _sawSelectDown = true;
          _favHoldFired = false;
          _holdController.forward(from: 0); // fills the heart over 500ms
          return KeyEventResult.handled;
        }
        if (event is KeyUpEvent) {
          // A press this row actually started, released before the hold
          // completed → tap (play). A key-up with no matching key-down
          // (focus arrived mid-press) is swallowed, never played.
          final wasPress = _sawSelectDown && !_favHoldFired;
          _sawSelectDown = false;
          _holdController.reset();
          _favHoldFired = false;
          if (wasPress) widget.onTap();
          return KeyEventResult.handled;
        }
        // Swallow auto-repeat while the key is held.
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovered = true);
          // Pointer platforms: hovering IS the "focus" that drives the two-pane
          // preview stage — but only once the pointer RESTS. Retargeting on
          // contact made the stage's own buttons unreachable: every row crossed
          // on the way to Watch/Record repointed it, so by the time the cursor
          // arrived the panel belonged to some channel swept past en route.
          // A sweep leaves each row well inside this window.
          //
          // The stage's 900ms dwell does NOT cover this — it only delays
          // OPENING the stream; the panel's identity, and with it the buttons,
          // always changed on the first pixel.
          if (widget.isTelevision) return;
          final armedFor = widget.channel;
          _hoverIntent?.cancel();
          _hoverIntent = Timer(_hoverIntentDelay, () {
            // Recycled under a stationary pointer (wheel-scrolling the grid):
            // the row aimed at is gone, and pointing the stage at whatever slid
            // underneath is not what the user asked for. Scrolling has never
            // retargeted the stage — onEnter doesn't re-fire on recycle — and
            // this keeps it that way.
            if (!mounted || !identical(widget.channel, armedFor)) return;
            widget.onPointerRest?.call();
          });
        },
        onExit: (_) {
          _hoverIntent?.cancel();
          _hoverIntent = null;
          setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          // Touch/desktop counterpart of TV's hold-OK. The row had no
          // long-press before, so this adds a gesture rather than
          // reinterpreting one.
          onLongPress: widget.onOpenListPicker,
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
  ///   always on touch (no hover there). Tapping it opens the list picker so
  ///   the channel's destination is a choice, not an assumption.
  Widget _buildFavTrailing() {
    // Describes what HOLD OK will actually do, so the hint can't promise a
    // picker on a remote that is really going to toggle the favorite.
    final picksList = widget.onOpenListPicker != null && widget.hasCustomLists;
    if (widget.onFavoriteToggle == null && !picksList) {
      return const SizedBox.shrink();
    }

    // In a list the user made, but not favourited: a quiet bookmark so the
    // row still reads as "saved somewhere" without competing with the heart.
    final marksListOnly = widget.inAnyList && !widget.isFavorited;

    if (widget.isTelevision) {
      if (_focused) {
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: AnimatedBuilder(
            animation: _holdController,
            builder: (_, __) => _FavHint(
              favorited: widget.isFavorited,
              progress: _holdController.value,
              picksList: picksList,
            ),
          ),
        );
      }
      if (widget.isFavorited) {
        return const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(
            Icons.favorite_rounded,
            size: 18,
            color: Color(0xFFF43F5E),
          ),
        );
      }
      if (marksListOnly) {
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(
            Icons.bookmark_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    if (widget.onFavoriteToggle == null) {
      return marksListOnly
          ? Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.bookmark_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            )
          : const SizedBox.shrink();
    }

    final show =
        widget.isFavorited || marksListOnly || _active || _isTouchMobile;
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: _FavButton(
        favorited: widget.isFavorited,
        inAnyList: widget.inAnyList,
        // Pointer devices: the heart asks WHERE the channel should go rather
        // than assuming Favorites. The picker offers Favorites and "Create
        // new list", so it answers the plain case in the same one tap it
        // used to take. Falls back to a direct toggle only for rows with no
        // picker at all.
        onTap: () {
          final openPicker = widget.onOpenListPicker;
          if (openPicker != null) {
            openPicker();
            return;
          }
          widget.onFavoriteToggle!(!widget.isFavorited);
        },
      ),
    );
  }
}

/// The in-row now/next block (redesign): what's airing right now, how far in
/// it is, and what's up next — the guide readable without focusing anything.
///
/// Paints synchronously from whatever the service already knows (an XMLTV
/// guide answers locally and instantly — the common case, and no network is
/// involved for it at all). Only a channel with no local answer needs a
/// per-stream request, and those are deliberately rationed:
///
/// - **Dwell gate.** A row must stay mounted [_fetchDwell] before it asks
///   for anything, so channels flying past under a scroll never queue work
///   (their timer dies with them).
/// - **Politeness budget.** At most [_maxConcurrentRowFetches] rows may have
///   a request outstanding at once, app-wide. A row that finds the budget
///   full re-arms instead of queuing, so a screenful fills in progressively
///   rather than firing two dozen requests the instant scrolling stops.
///
/// Both exist because a big Xtream list has no XMLTV fallback to lean on:
/// without rationing, browsing a 50k-channel guide would fire one
/// `get_short_epg` per channel seen — enough to jank the UI decoding replies
/// and enough for a panel to rate-limit the account.
///
/// A slow ticker advances the progress bar and rolls past programme
/// boundaries; the service cache is the staleness oracle (a null peek means
/// "time to re-ask").
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
  /// How long a row must sit still before it may ask the panel for guide
  /// data — long enough that rows scrolled past never reach it. A remote
  /// arrows through a list far slower than a finger flings one, and TV
  /// hardware has the least headroom, so it waits longest.
  static Duration get _fetchDwell => PlatformUtil.isAndroidTvCached
      ? const Duration(milliseconds: 900)
      : const Duration(milliseconds: 450);

  /// First retry spacing when the budget below is full; successive misses
  /// back off (doubling, capped) so a screenful waiting on a stalled panel
  /// stops re-polling every second.
  static const Duration _budgetRetry = Duration(milliseconds: 1200);
  static const Duration _budgetRetryCap = Duration(seconds: 6);

  /// App-wide ceiling on row-initiated guide requests in flight. This is a
  /// UI-level politeness budget, distinct from the service's own transport
  /// throttle: the rail card, the schedule pane and the player are never
  /// gated by it, only the rows.
  ///
  /// Matched to the service's own transport concurrency (3) rather than set
  /// above it: a row admitted beyond that just waits in the service's queue,
  /// where it holds a UI slot while achieving nothing and can still time out
  /// waiting. Equal means an admitted row goes straight to the wire.
  static const int _maxConcurrentRowFetches = 3;
  static int _rowFetchesInFlight = 0;

  EpgNowNext? _data;
  String? _forUrl;
  Timer? _fetchDebounce;
  Timer? _ticker;

  /// Set while THIS row holds one of the budget slots, so the release path
  /// can never double-decrement (dispose racing a completing fetch).
  bool _holdsBudget = false;

  /// Consecutive times this row found the budget full — drives the backoff.
  int _budgetMisses = 0;

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
    // A row scrolled away mid-request must hand its slot back — the reply is
    // still cached by the service, it just no longer has anyone to paint it.
    _releaseBudget();
    super.dispose();
  }

  void _releaseBudget() {
    if (!_holdsBudget) return;
    _holdsBudget = false;
    _rowFetchesInFlight--;
  }

  void _onEpgContextChanged() {
    if (mounted) _sync();
  }

  void _sync() {
    _fetchDebounce?.cancel();
    _budgetMisses = 0; // a fresh subject deserves a fresh ladder
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

  void _scheduleFetch([Duration? delay]) {
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(delay ?? _fetchDwell, _fetch);
  }

  /// Next budget retry: 1.2s, 2.4s, 4.8s, then capped. A whole screenful can
  /// be waiting behind a stalled panel (a request can occupy a slot for tens
  /// of seconds), and polling every 1.2s until it drains is pure wakeups on
  /// hardware that can least afford them.
  Duration _nextBudgetRetry() {
    final ms = _budgetRetry.inMilliseconds * (1 << _budgetMisses.clamp(0, 3));
    return ms >= _budgetRetryCap.inMilliseconds
        ? _budgetRetryCap
        : Duration(milliseconds: ms);
  }

  Future<void> _fetch() async {
    final url = _forUrl;
    if (url == null) return;

    // A guide already in memory (XMLTV) answers without touching the
    // network, so it must never be held behind the request budget.
    final local = IptvEpgService.instance.peekNowNext(url);
    if (local != null) {
      if (mounted) setState(() => _data = local);
      return;
    }

    // Re-entrancy: this row may ALREADY be awaiting a reply. Cancelling the
    // debounce can't recall a timer that has fired, so a ticker tick or a
    // contextVersion bump lands here while the first call is still in its
    // await. One bool can only hand one slot back, so a second increment
    // would leak a slot permanently (four leaks = no row ever fetches
    // again). Let the outstanding call finish and check back.
    if (_holdsBudget) {
      _budgetMisses++;
      _scheduleFetch(_nextBudgetRetry());
      return;
    }

    if (_rowFetchesInFlight >= _maxConcurrentRowFetches) {
      _budgetMisses++;
      _scheduleFetch(_nextBudgetRetry()); // come back when a slot frees
      return;
    }
    _budgetMisses = 0;
    _holdsBudget = true;
    _rowFetchesInFlight++;
    try {
      final result = await IptvEpgService.instance.nowNext(url);
      if (!mounted || url != _forUrl) return;
      if (!result.isEmpty) setState(() => _data = result);
    } finally {
      _releaseBudget();
    }
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
                    flex:
                        1000 -
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

  /// Hold opens the list picker rather than toggling the favourite outright.
  final bool picksList;

  const _FavHint({
    required this.favorited,
    required this.progress,
    this.picksList = false,
  });

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
                picksList
                    ? Icons.playlist_add_rounded
                    : done
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 16,
                color: picksList
                    ? Color.lerp(
                        Colors.white.withValues(alpha: 0.7),
                        HomeTheme.focusGold,
                        progress,
                      )!
                    : heartColor,
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
            Color.alphaBlend(
              brand.withValues(alpha: 0.16),
              const Color(0xFF1E2030),
            ),
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
                    // Dedicated disk store: the default manager holds 200
                    // objects, so a big guide re-downloaded logos on every
                    // scroll-back.
                    cacheManager: DebrifyImageCache.iptvLogos,
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
  final bool inAnyList;
  final VoidCallback onTap;
  const _FavButton({
    required this.favorited,
    required this.onTap,
    this.inAnyList = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      // The icon is a heart but the action is "choose where this goes", and
      // nothing else on the row says so. The schedule button beside it is
      // already labelled, so this matches rather than introduces a habit.
      message: 'Save to a list',
      // Hover only. Left at the default, Tooltip registers its own
      // LongPressGestureRecognizer on pointer-down for touch devices; it sits
      // deeper than the row's GestureDetector, so its timer fires first, it
      // wins the arena, and a touch long-press ON the heart would show this
      // label instead of opening the picker it describes. Hover is installed
      // independently of triggerMode, so the desktop affordance survives.
      triggerMode: TooltipTriggerMode.manual,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              favorited
                  ? Icons.favorite_rounded
                  : inAnyList
                  // Saved in a list the user made, just not favourited — show
                  // it as saved rather than as an empty heart.
                  ? Icons.bookmark_rounded
                  : Icons.favorite_border_rounded,
              size: 18,
              color: favorited
                  ? const Color(0xFFF43F5E)
                  : Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
