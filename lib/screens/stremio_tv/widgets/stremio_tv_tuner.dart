import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_addon.dart';
import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';
import '../stremio_tv_service.dart';

/// "The Tuner" — a cinematic channel-surfing experience for Stremio TV.
///
/// On wide screens (TV / laptop, width >= 900) it renders a full-bleed
/// [_Stage] of the focused channel's now-playing title above a horizontal
/// [_Dial] of channel cards you surf with the D-pad. On narrow screens
/// (phone portrait) it becomes a full-screen vertical channel pager.
///
/// The wall is *alive*: progress bars tick in real time and a channel's
/// card/stage flips itself the moment its time slot rolls over — you watch
/// the broadcast change while you sit there.
///
/// Focus is intentionally unchanged from the old list: [rowFocusNodes] stays
/// one-node-per-channel in [allChannels] order, so the screen header's
/// existing down-arrow handoff keeps working untouched.
class StremioTvTuner extends StatefulWidget {
  /// Channels in display order (already search-filtered by the screen).
  final List<StremioTvChannel> channels;

  /// The screen's full channel list — focus nodes are indexed by this.
  final List<StremioTvChannel> allChannels;

  /// One focus node per channel in [allChannels] order (owned by the screen).
  final List<FocusNode> rowFocusNodes;

  final StremioTvService service;
  final int Function(StremioTvChannel channel) rotationFor;
  final int mixSalt;
  final bool hideNowPlaying;
  final Set<String> loadingChannelIds;

  /// Kick off a lazy item load for [channel] (no-op if already loaded).
  final void Function(StremioTvChannel channel) ensureLoaded;

  /// Tune in: open the cinematic detail screen for the channel's now-playing.
  final void Function(StremioTvChannel channel) onOpenDetail;

  /// Play the channel's now-playing item immediately ("Just Watch").
  final void Function(StremioTvChannel channel) onPlay;

  /// Maps a channel's raw slot progress to the progress to *display*. The
  /// host caps/jitters this per the "max start %" setting so every progress
  /// bar matches where playback will actually join.
  final double Function(StremioTvChannel channel, double rawProgress)
      displayProgress;

  final void Function(StremioTvChannel channel) onToggleFavorite;
  final void Function(StremioTvChannel channel) onShowGuide;
  final void Function(StremioTvChannel channel)? onEditLocal;
  final void Function(StremioTvChannel channel)? onExportLocal;

  /// D-pad left at the first card → hand focus to the app sidebar.
  final VoidCallback onFocusSidebar;

  /// D-pad up from a card → hand focus back to the screen header.
  final VoidCallback onFocusHeader;

  /// Reports the focused channel's index within [allChannels].
  final void Function(int realIndex) onFocusedIndexChanged;

  const StremioTvTuner({
    super.key,
    required this.channels,
    required this.allChannels,
    required this.rowFocusNodes,
    required this.service,
    required this.rotationFor,
    required this.mixSalt,
    required this.hideNowPlaying,
    required this.loadingChannelIds,
    required this.ensureLoaded,
    required this.onOpenDetail,
    required this.onPlay,
    required this.displayProgress,
    required this.onToggleFavorite,
    required this.onShowGuide,
    required this.onFocusSidebar,
    required this.onFocusHeader,
    required this.onFocusedIndexChanged,
    this.onEditLocal,
    this.onExportLocal,
  });

  @override
  State<StremioTvTuner> createState() => _StremioTvTunerState();
}

class _StremioTvTunerState extends State<StremioTvTuner> {
  /// Drives the live "broadcast" — re-evaluates now-playing every second so
  /// progress bars sweep and slot rollovers flip themselves on screen.
  Timer? _tick;

  /// Channel id currently driving the Stage (wide) / page (narrow).
  String? _activeId;

  /// Latest focused channel id, awaiting the focus-settle debounce before it
  /// becomes [_activeId] and triggers the heavy Stage swap.
  String? _pendingId;
  Timer? _settle;

  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _activeId = widget.channels.isNotEmpty ? widget.channels.first.id : null;
    // Slots are 45–90 min, so a coarse tick keeps the broadcast "alive"
    // (sweeping progress, self-flipping slot rollovers) without rebuilding
    // the Stage + Dial every second on low-end TV hardware.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(StremioTvTuner old) {
    super.didUpdateWidget(old);
    // Keep the active channel valid as search/sort reshuffles the list.
    if (_activeId == null ||
        !widget.channels.any((c) => c.id == _activeId)) {
      _activeId = widget.channels.isNotEmpty ? widget.channels.first.id : null;
      _pendingId = _activeId;
      _settle?.cancel();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _settle?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // --- Channel ident ------------------------------------------------------

  /// A rich, deterministic accent per channel — like a TV channel's brand
  /// colour. Stable across rebuilds, distinct between neighbours.
  static const List<Color> _idents = [
    Color(0xFF6C5CE7), // indigo
    Color(0xFFE84393), // magenta
    Color(0xFF00B894), // emerald
    Color(0xFFE17055), // coral
    Color(0xFF0984E3), // azure
    Color(0xFFFDCB6E), // amber
    Color(0xFF00CEC9), // teal
    Color(0xFFA29BFE), // lavender
  ];

  Color _identFor(StremioTvChannel c) =>
      _idents[c.id.hashCode.abs() % _idents.length];

  StremioTvNowPlaying? _nowPlaying(StremioTvChannel c) => widget.service
      .getNowPlaying(c, rotationMinutes: widget.rotationFor(c), salt: widget.mixSalt);

  StremioTvNowPlaying? _nextPlaying(StremioTvChannel c) => widget.service
      .getNextPlaying(c, rotationMinutes: widget.rotationFor(c), salt: widget.mixSalt);

  /// Progress to render on a card/stage — capped per the host's "max
  /// start %" setting so the bar agrees with where playback will join.
  double _displayProgress(StremioTvChannel c, StremioTvNowPlaying? np) =>
      np == null ? 0.0 : widget.displayProgress(c, np.progress);

  int _realIndex(StremioTvChannel c) =>
      widget.allChannels.indexWhere((x) => x.id == c.id);

  FocusNode? _nodeFor(StremioTvChannel c) {
    final i = _realIndex(c);
    return (i >= 0 && i < widget.rowFocusNodes.length)
        ? widget.rowFocusNodes[i]
        : null;
  }

  void _setActive(StremioTvChannel c) {
    if (_pendingId == c.id) return;
    _pendingId = c.id;
    // Report the focused channel to the host immediately — it is cheap
    // bookkeeping (no rebuild) and must stay current so header→down returns
    // to the card the user is actually on, even mid-surf.
    final ri = widget.allChannels.indexWhere((x) => x.id == c.id);
    if (ri >= 0) widget.onFocusedIndexChanged(ri);
    // Surfing must stay instant. The Dial highlight is cheap, local card
    // state and already moved; only the heavy full-bleed Stage swap is
    // debounced to focus-settle (Netflix hero/rail pattern), so holding
    // left/right no longer queues a backlog of image decodes.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final id = _pendingId;
      if (id == null || _activeId == id) return;
      setState(() => _activeId = id);
    });
  }

  StremioTvChannel? get _activeChannel {
    for (final c in widget.channels) {
      if (c.id == _activeId) return c;
    }
    return widget.channels.isNotEmpty ? widget.channels.first : null;
  }

  // --- Long-press quick actions ------------------------------------------

  Future<void> _openActions(StremioTvChannel channel) async {
    final ident = _identFor(channel);
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101015),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        Widget tile(IconData icon, String label, VoidCallback onTap,
            {Color? tint}) {
          return ListTile(
            leading: Icon(icon, color: tint ?? Colors.white70),
            title: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.of(ctx).pop();
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(children: [
                  Container(width: 4, height: 26,
                    decoration: BoxDecoration(
                        color: ident,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(channel.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              tile(Icons.play_arrow_rounded, 'Play this channel now',
                  () => widget.onPlay(channel), tint: ident),
              if (!widget.hideNowPlaying)
                tile(Icons.info_outline_rounded, 'View details',
                    () => widget.onOpenDetail(channel)),
              if (!widget.hideNowPlaying)
                tile(Icons.live_tv_rounded, 'Channel guide',
                    () => widget.onShowGuide(channel)),
              tile(
                channel.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                channel.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                () => widget.onToggleFavorite(channel),
                tint: channel.isFavorite ? Colors.amber : null,
              ),
              if (channel.isLocal && widget.onEditLocal != null)
                tile(Icons.edit_rounded, 'Edit local catalog',
                    () => widget.onEditLocal!(channel)),
              if (channel.isLocal && widget.onExportLocal != null)
                tile(Icons.copy_all_rounded, 'Copy catalog JSON',
                    () => widget.onExportLocal!(channel)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // --- Channels overview (mobile) ----------------------------------------

  /// A scannable list of every channel + what's on right now. Tapping a
  /// row jumps the pager straight to that channel.
  void _openChannelList() {
    Timer? sheetTick;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101015),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        expand: false,
        builder: (ctx, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setSheet) {
            // Refresh as channels lazily load and progress ticks. 5s (not
            // 1s) — rebuilding the whole list + restarting every row's
            // image resolution every second janks long lists on low-end
            // TVs, and slots are 45–90 min so a coarse tick is plenty.
            sheetTick ??= Timer.periodic(const Duration(seconds: 5), (_) {
              if (ctx.mounted) setSheet(() {});
            });
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 2, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('All channels',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: widget.channels.length,
                    itemBuilder: (ctx, i) =>
                        _channelListRow(widget.channels[i], ctx),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ).whenComplete(() => sheetTick?.cancel());
  }

  Widget _channelListRow(StremioTvChannel channel, BuildContext ctx) {
    widget.ensureLoaded(channel);
    final ident = _identFor(channel);
    final np = widget.hideNowPlaying ? null : _nowPlaying(channel);
    final poster = np?.item.poster;
    final active = channel.id == _activeId;
    return Material(
      color: active ? ident.withValues(alpha: 0.16) : Colors.transparent,
      child: InkWell(
        onTap: () {
          // Resolve by id at tap time — the list can reshuffle/shrink while
          // the sheet is open (lazy-load may drop an empty channel), so the
          // build-time index `i` is not safe to jump with.
          final idx =
              widget.channels.indexWhere((c) => c.id == channel.id);
          Navigator.of(ctx).pop();
          if (idx >= 0 && _pageController.hasClients) {
            _pageController.jumpToPage(idx);
            _setActive(widget.channels[idx]);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 42,
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: ident,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 40,
                  height: 60,
                  child: poster != null
                      ? CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          errorWidget: (_, __, ___) =>
                              _listThumbFallback(ident, channel),
                        )
                      : _listThumbFallback(ident, channel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.hideNowPlaying
                          ? 'Now playing hidden'
                          : (np?.item.name ??
                              (widget.loadingChannelIds.contains(channel.id)
                                  ? 'Tuning in…'
                                  : 'No broadcast')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                    if (np != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: widget.displayProgress(channel, np.progress)
                              .clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.14),
                          valueColor: AlwaysStoppedAnimation(ident),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (channel.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(Icons.star_rounded,
                      size: 16, color: Color(0xFFFFC107)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listThumbFallback(Color ident, StremioTvChannel channel) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ident.withValues(alpha: 0.35), const Color(0xFF111118)],
        ),
      ),
      child: Icon(
        channel.type == 'series'
            ? Icons.live_tv_rounded
            : Icons.movie_rounded,
        size: 18,
        color: Colors.white.withValues(alpha: 0.3),
      ),
    );
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return wide ? _buildWide() : _buildNarrow();
      },
    );
  }

  // --- Wide: Stage + Dial -------------------------------------------------

  Widget _buildWide() {
    final active = _activeChannel;
    if (active != null) widget.ensureLoaded(active);

    // Only channels that have a focus node are renderable in the Dial.
    // Driving itemCount/navigation off this list (instead of
    // widget.channels with a SizedBox.shrink fallback) avoids a
    // counted-but-invisible blank slot that swallows D-pad focus.
    final dial = widget.channels.where((c) => _nodeFor(c) != null).toList();
    assert(
      dial.length == widget.channels.length,
      'Dial dropped ${widget.channels.length - dial.length} channel(s) with '
      'no focus node — channels must be a subset of allChannels.',
    );

    return Column(
      children: [
        // Stage flexes; the Dial is a fixed band so its fixed-size cards can
        // never overflow on short windows.
        Expanded(
          child: AnimatedSwitcher(
            // Fade only — scaling a full-bleed image is GPU-heavy on TV.
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: active == null
                ? const SizedBox.shrink()
                : Builder(
                    // Key on the Builder — AnimatedSwitcher keys off its
                    // direct child, so the cross-fade must trigger here.
                    key: ValueKey(active.id),
                    builder: (_) {
                      final np = _nowPlaying(active);
                      return _Stage(
                        channel: active,
                        ident: _identFor(active),
                        nowPlaying: np,
                        nextPlaying: _nextPlaying(active),
                        displayProgress: _displayProgress(active, np),
                        hideNowPlaying: widget.hideNowPlaying,
                        loading:
                            widget.loadingChannelIds.contains(active.id),
                      );
                    },
                  ),
          ),
        ),
        SizedBox(
          // 112/0.667 ≈ 168 card + 28 vertical margin + 18 padding ≈ 214;
          // a slimmer Dial gives the Stage more height on short TVs.
          height: 218,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              itemCount: dial.length,
              itemBuilder: (context, i) {
                final channel = dial[i];
                widget.ensureLoaded(channel);
                final node = _nodeFor(channel)!;
                final np = _nowPlaying(channel);
                return _DialCard(
                  key: ValueKey(channel.id),
                  channel: channel,
                  ident: _identFor(channel),
                  focusNode: node,
                  nowPlaying: np,
                  displayProgress: _displayProgress(channel, np),
                  hideNowPlaying: widget.hideNowPlaying,
                  loading: widget.loadingChannelIds.contains(channel.id),
                  onFocused: () => _setActive(channel),
                  // Lean-back: clicking a channel tunes straight in. Details
                  // live in the long-press sheet for anyone who wants them.
                  onSelect: () => widget.onPlay(channel),
                  onLongPress: () => _openActions(channel),
                  onLeft: () {
                    // Resolve position by id at press time — the list can
                    // reshuffle/shrink while a card is focused, so the
                    // build-time index is not safe to navigate with.
                    final live = widget.channels
                        .where((c) => _nodeFor(c) != null)
                        .toList();
                    final cur =
                        live.indexWhere((c) => c.id == channel.id);
                    if (cur <= 0) {
                      widget.onFocusSidebar();
                    } else {
                      _nodeFor(live[cur - 1])?.requestFocus();
                    }
                  },
                  onRight: () {
                    final live = widget.channels
                        .where((c) => _nodeFor(c) != null)
                        .toList();
                    final cur =
                        live.indexWhere((c) => c.id == channel.id);
                    if (cur >= 0 && cur < live.length - 1) {
                      _nodeFor(live[cur + 1])?.requestFocus();
                    }
                  },
                  onUp: widget.onFocusHeader,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // --- Narrow: full-screen vertical channel pager -------------------------

  Widget _buildNarrow() {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: widget.channels.length,
      onPageChanged: (i) {
        final c = widget.channels[i];
        widget.ensureLoaded(c);
        if (i + 1 < widget.channels.length) {
          widget.ensureLoaded(widget.channels[i + 1]);
        }
        _setActive(c);
      },
      itemBuilder: (context, i) {
        final channel = widget.channels[i];
        widget.ensureLoaded(channel);
        final np = _nowPlaying(channel);
        return GestureDetector(
          onTap: () => widget.onPlay(channel),
          onLongPress: () => _openActions(channel),
          child: _Stage(
            channel: channel,
            ident: _identFor(channel),
            nowPlaying: np,
            nextPlaying: _nextPlaying(channel),
            displayProgress: _displayProgress(channel, np),
            hideNowPlaying: widget.hideNowPlaying,
            loading: widget.loadingChannelIds.contains(channel.id),
            showSurfHint: true,
            onOpenList: _openChannelList,
          ),
        );
      },
    );
  }
}

// =========================================================================
// The Stage — the cinematic now-playing hero.
// =========================================================================

class _Stage extends StatelessWidget {
  final StremioTvChannel channel;
  final Color ident;
  final StremioTvNowPlaying? nowPlaying;
  final StremioTvNowPlaying? nextPlaying;

  /// Capped/jittered progress to draw on the LIVE bar (honours the "max
  /// start %" setting so it matches where playback will join).
  final double displayProgress;
  final bool hideNowPlaying;
  final bool loading;
  final bool showSurfHint;

  /// When set (mobile), the top-right pill becomes a tappable "Channels"
  /// button that opens the all-channels overview list.
  final VoidCallback? onOpenList;

  const _Stage({
    required this.channel,
    required this.ident,
    required this.nowPlaying,
    required this.nextPlaying,
    required this.displayProgress,
    required this.hideNowPlaying,
    required this.loading,
    this.showSurfHint = false,
    this.onOpenList,
  });

  @override
  Widget build(BuildContext context) {
    final item = nowPlaying?.item;
    final bg = item?.background ?? item?.poster;
    final blurArt = hideNowPlaying;

    // Only the mobile pager passes onOpenList. There the content sits at
    // the very bottom of a full-screen page, so it must clear the nav bar
    // *and* any floating system button (e.g. Samsung's assistant/Menu
    // pill). The wide TV Stage keeps the slim inset so it doesn't steal
    // height from the Dial below it.
    final isNarrow = onOpenList != null;
    final bottomInset = isNarrow
        ? 30.0 + MediaQuery.of(context).padding.bottom + 72.0
        : 30.0;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF09090F)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cinematic backdrop.
          if (bg != null)
            Builder(
              builder: (context) {
                Widget art = CachedNetworkImage(
                  imageUrl: bg,
                  fit: BoxFit.cover,
                  memCacheWidth: blurArt ? 480 : 900,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
                if (blurArt) {
                  art = ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: art,
                  );
                }
                return ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.18),
                    BlendMode.darken,
                  ),
                  child: art,
                );
              },
            ),
          // Channel-ident wash + readability scrims.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [
                  const Color(0xFF09090F).withValues(alpha: 0.96),
                  const Color(0xFF09090F).withValues(alpha: 0.55),
                  ident.withValues(alpha: 0.10),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Color(0xCC09090F), Color(0x0009090F)],
              ),
            ),
          ),
          // Content.
          Padding(
            padding: EdgeInsets.fromLTRB(40, 28, 40, bottomInset),
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  // Anchors bottom-left and scales the whole block down to
                  // fit short TV heights — it can never overflow into the
                  // Dial or clip LIVE / progress / UP NEXT.
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                _channelTag(),
                const SizedBox(height: 14),
                if (item == null)
                  _tuningState()
                else if (hideNowPlaying) ...[
                  // Spoiler-free: never reveal the title/meta/up-next in
                  // text. The live clock is not a spoiler, so it stays.
                  _hiddenState(),
                  const SizedBox(height: 18),
                  _liveBar(),
                ] else ...[
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(blurRadius: 18, color: Colors.black)
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _metaRow(item),
                  if (item.description != null &&
                      item.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StageDescription(
                      text: item.description!.trim(),
                      title: item.name,
                      ident: ident,
                      // Only the mobile pager can tap "Read more"; the TV
                      // Stage isn't focusable (details live in the Dial
                      // long-press sheet), so it keeps the slim 2-line
                      // synopsis and no dead affordance.
                      interactive: isNarrow,
                    ),
                  ],
                  const SizedBox(height: 18),
                  _liveBar(),
                  if (nextPlaying != null) ...[
                    const SizedBox(height: 12),
                    _upNext(),
                  ],
                ],
              ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showSurfHint)
            Positioned(
              top: 14,
              right: 18,
              child: _hintPill(),
            ),
          if (onOpenList != null)
            Positioned(
              top: 14,
              left: 18,
              child: GestureDetector(
                onTap: onOpenList,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.format_list_bulleted_rounded,
                        size: 16, color: Colors.white),
                    SizedBox(width: 7),
                    Text('Channels',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _channelTag() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: ident,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: ident.withValues(alpha: 0.55),
                  blurRadius: 16,
                  spreadRadius: 1)
            ],
          ),
          child: Text(
            'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            channel.displayName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metaRow(StremioMeta item) {
    final bits = <Widget>[];
    void add(Widget w) {
      if (bits.isNotEmpty) {
        bits.add(_dot());
      }
      bits.add(w);
    }

    if (item.year != null && item.year!.isNotEmpty) {
      add(Text(item.year!, style: _metaStyle));
    }
    if (item.imdbRating != null) {
      add(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFC107)),
        const SizedBox(width: 3),
        Text(item.imdbRating!.toStringAsFixed(1), style: _metaStyle),
      ]));
    }
    if (item.genres != null && item.genres!.isNotEmpty) {
      // Flexible + ellipsis so long genre lists truncate instead of
      // overflowing the row (the stripes seen above LIVE).
      add(Flexible(
        child: Text(
          item.genres!.take(3).join(' · '),
          style: _metaStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ));
    }
    if (bits.isEmpty) return const SizedBox.shrink();
    return Row(children: bits);
  }

  static const _metaStyle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
        ),
      );

  Widget _liveBar() {
    final np = nowPlaying;
    final progress = displayProgress;
    return Row(
      children: [
        _LivePip(color: ident),
        const SizedBox(width: 8),
        const Text('LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            )),
        const SizedBox(width: 14),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              valueColor: AlwaysStoppedAnimation(ident),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          np?.progressText ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _upNext() {
    final n = nextPlaying!;
    return Opacity(
      opacity: 0.72,
      child: Row(
        children: [
          Text(
            'UP NEXT',
            style: TextStyle(
              color: ident,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              n.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tuningState() {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(ident),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          loading ? 'Tuning in…' : 'No broadcast on this channel',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _hiddenState() {
    return Row(
      children: [
        Icon(Icons.visibility_off_rounded,
            size: 26, color: Colors.white.withValues(alpha: 0.5)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Now playing hidden — tune in to reveal',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _hintPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: const [
        Icon(Icons.swipe_vertical_rounded, size: 15, color: Colors.white70),
        SizedBox(width: 6),
        Text('Surf',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Stage synopsis: shows up to 4 lines and, only when the text actually
/// overflows that, a "Read more" that opens the full synopsis in a sheet.
/// A sheet (not inline expand) because the Stage body lives inside a
/// scale-down FittedBox — expanding inline would just shrink everything.
class _StageDescription extends StatelessWidget {
  final String text;
  final String title;
  final Color ident;

  /// Mobile pager only: render more lines and a tappable "Read more".
  /// On TV this is false → slim 2-line synopsis, no affordance.
  final bool interactive;

  const _StageDescription({
    required this.text,
    required this.title,
    required this.ident,
    required this.interactive,
  });

  static const _style = TextStyle(
    color: Color(0xB8FFFFFF), // white @ ~0.72
    fontSize: 14.5,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    // TV: slim 2-line synopsis, no affordance. Return early so the Stage's
    // frequent rebuilds (15s tick + every surf) don't lay out a throwaway
    // TextPainter whose overflow result is never used here.
    if (!interactive) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _style,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: _style),
          maxLines: 4,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: c.maxWidth);
        final overflows = tp.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: _style,
            ),
            if (overflows) ...[
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showFull(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Read more',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.expand_more_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.95)),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showFull(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101015),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(children: [
                Container(
                  width: 4,
                  height: 26,
                  decoration: BoxDecoration(
                    color: ident,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A softly pulsing "on air" pip.
class _LivePip extends StatefulWidget {
  final Color color;
  const _LivePip({required this.color});

  @override
  State<_LivePip> createState() => _LivePipState();
}

class _LivePipState extends State<_LivePip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B5C),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B5C)
                    .withValues(alpha: 0.25 + 0.45 * t),
                blurRadius: 6 + 8 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

// =========================================================================
// The Dial — a single surfable channel card.
// =========================================================================

class _DialCard extends StatefulWidget {
  final StremioTvChannel channel;
  final Color ident;
  final FocusNode focusNode;
  final StremioTvNowPlaying? nowPlaying;

  /// Capped/jittered progress for the card's bottom strip (honours the
  /// "max start %" setting).
  final double displayProgress;
  final bool hideNowPlaying;
  final bool loading;
  final VoidCallback onFocused;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onUp;

  const _DialCard({
    super.key,
    required this.channel,
    required this.ident,
    required this.focusNode,
    required this.nowPlaying,
    required this.displayProgress,
    required this.hideNowPlaying,
    required this.loading,
    required this.onFocused,
    required this.onSelect,
    required this.onLongPress,
    required this.onLeft,
    required this.onRight,
    required this.onUp,
  });

  @override
  State<_DialCard> createState() => _DialCardState();
}

class _DialCardState extends State<_DialCard> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    // Surfing left/right repeats while the D-pad is held.
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        widget.onLeft();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        widget.onRight();
        return KeyEventResult.handled;
      }
    }
    // Everything else is edge-triggered: a held ENTER must not push the
    // detail route (or reopen the action sheet) on every repeat.
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.contextMenu) {
      widget.onLongPress();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.gameButtonA) {
      widget.onSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.nowPlaying?.item;
    final poster = item?.poster ?? item?.background;
    final ident = widget.ident;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          widget.onFocused();
          // Instant on TV — an animated scroll concurrent with the Stage
          // swap is a known jank source (CatalogItemTile does the same).
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
      },
      child: GestureDetector(
        onTap: () {
          widget.focusNode.requestFocus();
          widget.onSelect();
        },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 112,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? ident
                    : Colors.white.withValues(alpha: 0.07),
                width: _focused ? 2.5 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: ident.withValues(alpha: 0.5),
                        blurRadius: 26,
                        spreadRadius: 1,
                      )
                    ]
                  : const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      )
                    ],
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 0.667,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster != null && !widget.hideNowPlaying)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      memCacheWidth: 320,
                      placeholder: (_, __) => _placeholder(ident),
                      errorWidget: (_, __, ___) => _placeholder(ident),
                    )
                  else if (poster != null && widget.hideNowPlaying)
                    ImageFiltered(
                      imageFilter:
                          ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: CachedNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        errorWidget: (_, __, ___) => _placeholder(ident),
                      ),
                    )
                  else
                    _placeholder(ident),
                  // Bottom scrim for the live strip.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [Color(0xE6000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                  // Channel number badge.
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: ident,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        channelNumberLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  if (widget.channel.isFavorite)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.star_rounded,
                          size: 16, color: Color(0xFFFFC107)),
                    ),
                  // Title + live strip.
                  Positioned(
                    left: 9,
                    right: 9,
                    bottom: 9,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          // Spoiler-free mode shows the channel, never the
                          // hidden program's title.
                          widget.hideNowPlaying
                              ? widget.channel.catalog.name
                              : (item?.name ?? widget.channel.catalog.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: widget.displayProgress.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
                            valueColor:
                                AlwaysStoppedAnimation(ident),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get channelNumberLabel =>
      'CH ${widget.channel.channelNumber.toString().padLeft(2, '0')}';

  Widget _placeholder(Color ident) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ident.withValues(alpha: 0.35),
            const Color(0xFF111118),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          widget.channel.type == 'series'
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          color: Colors.white.withValues(alpha: 0.25),
          size: 30,
        ),
      ),
    );
  }
}
