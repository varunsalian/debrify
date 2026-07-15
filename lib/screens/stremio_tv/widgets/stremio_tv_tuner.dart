import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/home/home_theme.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/tv_keys.dart';
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

  /// The user's "Auto-refresh" setting: when true the tuner ticks every 15s
  /// so progress bars sweep and slot rollovers flip live; when false the
  /// broadcast only re-evaluates on interaction (this is the setting's sole
  /// consumer, so turning it off must visibly stop the live updates).
  final bool autoRefresh;

  /// Resolved native Android-TV flag. Forces the wide Stage+Dial layout (with
  /// D-pad channel switching) regardless of the constrained width — inside the
  /// app shell the sidebar rail trims the tuner slot below the 900px wide
  /// threshold, so a width-only check drops a real TV to the tap-only narrow
  /// pager and the remote can no longer change channels.
  final bool isTelevision;

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
    required this.autoRefresh,
    required this.isTelevision,
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
  /// A ValueNotifier so a surf step only rebuilds the Stage (via the
  /// ValueListenableBuilder in [_buildWide]) — the Home hero's model — instead
  /// of setState-ing the whole tuner and re-running every dial card.
  final ValueNotifier<String?> _activeId = ValueNotifier<String?>(null);

  /// Latest focused channel id, awaiting the focus-settle debounce before it
  /// becomes [_activeId] and triggers the heavy Stage swap.
  String? _pendingId;
  Timer? _settle;

  /// O(1) channel-id → index into [StremioTvTuner.allChannels] (and thus into
  /// [StremioTvTuner.rowFocusNodes]). Rebuilt whenever the widget updates.
  /// Replaces the per-lookup indexWhere scans that made every DPAD press and
  /// every rebuild O(n²) once genre expansion pushed the channel count into
  /// the hundreds.
  Map<String, int> _indexById = const {};

  final PageController _pageController = PageController();

  /// Drives the wide layout's horizontal channel dial. Needed on desktop so a
  /// mouse (no DPAD focus to auto-scroll) can pan the row: a vertical wheel is
  /// mapped to horizontal offset, and mouse/trackpad drag is enabled below.
  final ScrollController _dialScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _rebuildIndex();
    _activeId.value =
        widget.channels.isNotEmpty ? widget.channels.first.id : null;
    _syncTick();
  }

  /// Start/stop the 15s live-broadcast tick per the Auto-refresh setting.
  void _syncTick() {
    if (widget.autoRefresh) {
      _tick ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void didUpdateWidget(StremioTvTuner old) {
    super.didUpdateWidget(old);
    _rebuildIndex();
    _syncTick();
    if (_activeId.value == null ||
        !widget.channels.any((c) => c.id == _activeId.value)) {
      _activeId.value =
          widget.channels.isNotEmpty ? widget.channels.first.id : null;
      _pendingId = _activeId.value;
      _settle?.cancel();
    }
  }

  void _rebuildIndex() {
    // First-wins on duplicate ids (the addon service allows the same addon
    // installed twice with different config, which yields duplicate channel
    // ids) so the map agrees with every indexWhere fallback in this file.
    final map = <String, int>{};
    for (var i = 0; i < widget.allChannels.length; i++) {
      map.putIfAbsent(widget.allChannels[i].id, () => i);
    }
    _indexById = map;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _settle?.cancel();
    _activeId.dispose();
    _pageController.dispose();
    _dialScroll.dispose();
    super.dispose();
  }

  // --- Channel ident ------------------------------------------------------

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

  double _displayProgress(StremioTvChannel c, StremioTvNowPlaying? np) =>
      np == null ? 0.0 : widget.displayProgress(c, np.progress);

  int _realIndex(StremioTvChannel c) {
    final all = widget.allChannels;
    final i = _indexById[c.id];
    // Validate the cached index against the live list: the screen mutates its
    // channel/node lists *in place* when an empty channel is removed, so the
    // cache can be stale for the microtask window before the next rebuild
    // refreshes it. On a miss, re-sync the cache and answer from it (one
    // pass, and the same first-wins semantics as the warm path).
    if (i != null && i < all.length && all[i].id == c.id) return i;
    _rebuildIndex();
    return _indexById[c.id] ?? -1;
  }

  FocusNode? _nodeFor(StremioTvChannel c) {
    final i = _realIndex(c);
    return (i >= 0 && i < widget.rowFocusNodes.length)
        ? widget.rowFocusNodes[i]
        : null;
  }

  void _setActive(StremioTvChannel c) {
    if (_pendingId == c.id) return;
    _pendingId = c.id;
    final ri = _realIndex(c);
    if (ri >= 0) widget.onFocusedIndexChanged(ri);
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final id = _pendingId;
      if (id == null || _activeId.value == id) return;
      // The channel can be removed from the list during the 180ms settle
      // (empty lazy-load). Don't write a dead id: _channelById would render
      // channels.first while state pointed at the ghost until the next
      // rebuild reset it.
      if (!widget.channels.any((c) => c.id == id)) return;
      // Only the Stage's ValueListenableBuilder rebuilds — the dial cards
      // don't depend on the active id, so surfing never re-runs them...
      _activeId.value = id;
      // ...except when Auto-refresh is off: with the 15s tick cancelled a
      // surf settle is the only moment left to re-evaluate the dial cards'
      // now-playing/progress, otherwise they'd drift out of sync with the
      // Stage after a slot rollover. One cheap rebuild per settle.
      if (!widget.autoRefresh) setState(() {});
    });
  }

  StremioTvChannel? _channelById(String? id) {
    for (final c in widget.channels) {
      if (c.id == id) return c;
    }
    return widget.channels.isNotEmpty ? widget.channels.first : null;
  }

  /// Move focus [delta] steps from [channel] along the dial (left at the
  /// first card hands off to the sidebar). [buildIndex] is the card's dial
  /// index captured at build time — validated against the live channel list
  /// at press time, because a press can land in the window between the
  /// screen's in-place removal of an empty channel and the rebuild that
  /// refreshes the captured closures. O(1) in the common (unchanged) case.
  void _surf(StremioTvChannel channel, int buildIndex, int delta) {
    final live = widget.channels;
    final cur = (buildIndex >= 0 &&
            buildIndex < live.length &&
            live[buildIndex].id == channel.id)
        ? buildIndex
        : live.indexWhere((c) => c.id == channel.id);
    // Pressed card's channel vanished (removal landed this exact frame):
    // deliberately drop the press — the rebuild rescues focus momentarily,
    // and jumping a mid-dial press to the sidebar would be more surprising.
    if (cur < 0) return;
    final target = cur + delta;
    if (target < 0) {
      widget.onFocusSidebar();
      return;
    }
    if (target >= live.length) return;
    _nodeFor(live[target])?.requestFocus();
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
    final active = channel.id == _activeId.value;
    return Material(
      color: active ? ident.withValues(alpha: 0.16) : Colors.transparent,
      child: InkWell(
        onTap: () {
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
        // On a TV always use the wide Stage+Dial (D-pad channel switching) —
        // the sidebar rail can trim the slot below 900px, and the narrow pager
        // is tap-only, leaving the remote unable to change channels.
        final wide = widget.isTelevision || constraints.maxWidth >= 900;
        return wide ? _buildWide() : _buildNarrow();
      },
    );
  }

  // --- Wide: Stage + Dial -------------------------------------------------

  Widget _buildWide() {
    final dial = widget.channels.where((c) => _nodeFor(c) != null).toList();
    assert(
      dial.length == widget.channels.length,
      'Dial dropped ${widget.channels.length - dial.length} channel(s) with '
      'no focus node — channels must be a subset of allChannels.',
    );

    return Column(
      children: [
        Expanded(
          // No ValueKey remount on channel change: the Stage persists and
          // animates its content in place (text cascade, continuous Ken Burns
          // breathe) — the Home hero's model — instead of hard-swapping the
          // whole subtree every surf step. The ValueListenableBuilder scopes
          // a surf step's rebuild to the Stage alone.
          child: ValueListenableBuilder<String?>(
            valueListenable: _activeId,
            builder: (context, activeId, _) {
              final active = _channelById(activeId);
              if (active == null) return const SizedBox.shrink();
              widget.ensureLoaded(active);
              final np = _nowPlaying(active);
              return _Stage(
                channel: active,
                ident: _identFor(active),
                nowPlaying: np,
                nextPlaying: _nextPlaying(active),
                displayProgress: _displayProgress(active, np),
                hideNowPlaying: widget.hideNowPlaying,
                isTelevision: widget.isTelevision,
                loading: widget.loadingChannelIds.contains(active.id),
              );
            },
          ),
        ),
        // Dial area
        Container(
          height: 240,
          decoration: BoxDecoration(
            // Indigo-tinted wash (was flat black) so the dial shelf melts into
            // the Home page background instead of reading as a separate panel.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HomeTheme.bg.withValues(alpha: 0.0),
                HomeTheme.bg.withValues(alpha: 0.72),
              ],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            // Desktop can't move DPAD focus to auto-scroll and a vertical mouse
            // wheel doesn't pan a horizontal list, so translate the wheel to a
            // horizontal offset; ScrollConfiguration also enables mouse/trackpad
            // drag. Touch and DPAD focus-scroll are unaffected.
            child: Listener(
              onPointerSignal: (signal) {
                if (signal is! PointerScrollEvent) return;
                if (!_dialScroll.hasClients) return;
                // Only translate a VERTICAL wheel: a horizontal Scrollable
                // already applies horizontal (dx) deltas itself, so handling
                // those here too would double-scroll a trackpad swipe.
                final dy = signal.scrollDelta.dy;
                if (dy == 0) return;
                final target = (_dialScroll.offset + dy).clamp(
                  0.0,
                  _dialScroll.position.maxScrollExtent,
                );
                _dialScroll.jumpTo(target);
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: ListView.builder(
                  controller: _dialScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
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
                      isTelevision: widget.isTelevision,
                      onFocused: () => _setActive(channel),
                      onSelect: () => widget.onPlay(channel),
                      onLongPress: () => _openActions(channel),
                      onLeft: () => _surf(channel, i, -1),
                      onRight: () => _surf(channel, i, 1),
                      onUp: widget.onFocusHeader,
                    );
                  },
                ),
              ),
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
            isTelevision: widget.isTelevision,
            loading: widget.loadingChannelIds.contains(channel.id),
            onOpenList: _openChannelList,
            onOpenDetail: () => widget.onOpenDetail(channel),
          ),
        );
      },
    );
  }
}

// =========================================================================
// The Stage — the cinematic now-playing hero.
// =========================================================================

class _Stage extends StatefulWidget {
  final StremioTvChannel channel;
  final Color ident;
  final StremioTvNowPlaying? nowPlaying;
  final StremioTvNowPlaying? nextPlaying;
  final double displayProgress;
  final bool hideNowPlaying;
  final bool isTelevision;
  final bool loading;
  final VoidCallback? onOpenList;
  final VoidCallback? onOpenDetail;

  const _Stage({
    required this.channel,
    required this.ident,
    required this.nowPlaying,
    required this.nextPlaying,
    required this.displayProgress,
    required this.hideNowPlaying,
    required this.isTelevision,
    required this.loading,
    this.onOpenList,
    this.onOpenDetail,
  });

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with TickerProviderStateMixin {
  // Slow, endless Ken Burns breathe on the backdrop — same recipe as the Home
  // hero: a pure bottom-anchored zoom on an already-rasterised image, isolated
  // in a RepaintBoundary so only the backdrop layer re-rasters per frame. The
  // long duration keeps the motion barely-there.
  late final AnimationController _ken = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  );

  // Short cascade for the text block when the channel / now-playing changes:
  // tag, title, meta, plot and live bar slide-fade in with tiny staggers
  // instead of hard-swapping (the Home hero's _textFx, verbatim).
  late final AnimationController _textFx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1.0, // first build shows settled text; cascades start on change
  );

  bool _motionOk = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced-motion: hold the backdrop still, skip text cascades.
    _motionOk = !MediaQuery.of(context).disableAnimations;
    _syncKen();
  }

  /// Run the breathe only when something actually paints it: in blur mode —
  /// and on a channel with no backdrop yet (item still loading) — the backdrop
  /// AnimatedBuilder isn't in the tree, and a listener-less repeating
  /// controller would still force engine frames at 60fps for nothing.
  ///
  /// Never on TV: unlike the Home hero (a short strip), the Stage backdrop is
  /// near-full-screen, so the breathe re-rasters almost the whole frame 60fps
  /// forever. On weak TV GPUs that standing load is what makes everything
  /// drawn on top — dial focus pops, the quick-actions sheet, menu focus
  /// moves — feel sluggish, for motion that's barely perceptible anyway.
  void _syncKen() {
    final item = widget.nowPlaying?.item;
    final hasArt = (item?.background ?? item?.poster) != null;
    final wantKen =
        _motionOk && !widget.hideNowPlaying && hasArt && !widget.isTelevision;
    if (!wantKen) {
      _ken.stop();
    } else if (!_ken.isAnimating) {
      _ken.repeat(reverse: true);
    }
    if (!_motionOk) _textFx.value = 1.0;
  }

  @override
  void didUpdateWidget(_Stage old) {
    super.didUpdateWidget(old);
    _syncKen();
    final itemChanged =
        old.nowPlaying?.item.id != widget.nowPlaying?.item.id ||
            old.channel.id != widget.channel.id;
    if (itemChanged && _motionOk) {
      _textFx.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ken.dispose();
    _textFx.dispose();
    super.dispose();
  }

  /// Wraps one text-block line in its slice of the cascade: a quick fade plus
  /// a slight upward drift, offset by [from]..[to] of the controller.
  Widget _cascade(Widget child, double from, double to) {
    final curved = CurvedAnimation(
      parent: _textFx,
      curve: Interval(from, to, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, inner) => Transform.translate(
          offset: Offset(0, 10 * (1 - curved.value)),
          child: inner,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.nowPlaying?.item;
    final bg = item?.background ?? item?.poster;
    final blurArt = widget.hideNowPlaying;

    final isNarrow = widget.onOpenList != null;
    final bottomInset = isNarrow
        ? 30.0 + MediaQuery.of(context).padding.bottom + 72.0
        : 30.0;

    return DecoratedBox(
      // Base matches the Home page background (was a colder near-black), so a
      // channel with no backdrop and the Stage's lower fade both land on the
      // same indigo the rest of the app uses.
      decoration: const BoxDecoration(color: HomeTheme.bg),
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
                  // The Stage swaps a fresh full-bleed backdrop on every surf
                  // settle, so it uses the shared hero decode cap (1080 on
                  // TV) rather than an oversized decode per step.
                  memCacheWidth: blurArt
                      ? 480
                      : (widget.isTelevision
                          ? HomeTheme.heroBackdropCacheWidthTv
                          : HomeTheme.heroBackdropCacheWidth),
                  // On TV, snap the swap instead of the default 500ms opacity
                  // crossfade — that fade is a near-full-screen saveLayer per
                  // frame on every surf step. The text cascade still provides
                  // the transition polish.
                  fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
                  fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
                if (blurArt) {
                  art = ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: art,
                  );
                }
                if (widget.isTelevision) {
                  // A full-screen ColorFiltered(darken) is a saveLayer that
                  // gets re-composited on every surf settle — heavy on TV. For
                  // this subtle 12% darken a plain black overlay (srcOver) reads
                  // the same but costs nothing: no saveLayer, no blend pass.
                  art = Stack(
                    fit: StackFit.expand,
                    children: [
                      art,
                      Container(color: Colors.black.withValues(alpha: 0.12)),
                    ],
                  );
                } else {
                  art = ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.12),
                      BlendMode.darken,
                    ),
                    child: art,
                  );
                }
                // Ken Burns breathe (Home hero recipe). Skipped in blur mode —
                // re-running the 32px blur every zoom frame would hammer the
                // weak TV GPU for motion that's invisible under the blur.
                // The RepaintBoundary confines the per-frame re-raster to the
                // backdrop; the ClipRect is load-bearing — the bottom-anchored
                // scale paints upward past the Stage at paint time, which the
                // Stack's own clip never catches.
                if (blurArt) return art;
                return RepaintBoundary(
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _ken,
                      builder: (context, child) {
                        final t = Curves.easeInOut.transform(_ken.value);
                        return Transform.scale(
                          scale: 1.0 + 0.06 * t,
                          alignment: Alignment.bottomCenter,
                          filterQuality: FilterQuality.low,
                          child: child,
                        );
                      },
                      child: art,
                    ),
                  ),
                );
              },
            ),
          // Multi-layer scrim for depth.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.6,
                colors: [
                  widget.ident.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [
                  HomeTheme.bg.withValues(alpha: 0.97),
                  HomeTheme.bg.withValues(alpha: 0.50),
                  widget.ident.withValues(alpha: 0.06),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Legibility scrims share the page hue (0x0D0B1A = HomeTheme.bg) so
          // the darkened corners meet the indigo base without a colour seam.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Color(0xDD0D0B1A), Color(0x000D0B1A)],
              ),
            ),
          ),
          // Side vignette for widescreen depth.
          if (!isNarrow)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0x660D0B1A),
                    Color(0x000D0B1A),
                    Color(0x000D0B1A),
                    Color(0x330D0B1A),
                  ],
                  stops: [0.0, 0.15, 0.85, 1.0],
                ),
              ),
            ),
          // Content with entrance animation.
          Padding(
            padding: EdgeInsets.fromLTRB(
              isNarrow ? 28 : 48,
              isNarrow ? 56 : 28,
              isNarrow ? 28 : 48,
              bottomInset,
            ),
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth),
                    child: _buildContent(item, isNarrow),
                  ),
                ),
              ),
            ),
          ),
          if (widget.onOpenDetail != null)
            Positioned(
              top: 14,
              right: 18,
              child: GestureDetector(
                onTap: widget.onOpenDetail,
                child: _glassPill(
                  icon: Icons.info_outline_rounded,
                  label: 'Details',
                ),
              ),
            ),
          if (widget.onOpenList != null)
            Positioned(
              top: 14,
              left: 18,
              child: GestureDetector(
                onTap: widget.onOpenList,
                child: _glassPill(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'Channels',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(StremioMeta? item, bool isNarrow) {
    // Staggered cascade offsets mirror the Home hero: tag first, then title,
    // meta, plot, and the live bar/up-next trailing — a channel surf reads as
    // one composed entrance instead of a hard text swap.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _cascade(_channelTag(), 0.0, 0.6),
        const SizedBox(height: 16),
        if (item == null)
          _tuningState()
        else if (widget.hideNowPlaying) ...[
          _hiddenState(),
          const SizedBox(height: 20),
          _cascade(_liveBar(), 0.32, 1.0),
        ] else ...[
          _cascade(
            Text(
              item.name,
              maxLines: isNarrow ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isNarrow ? 28 : 44,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                shadows: const [
                  Shadow(blurRadius: 16, color: Colors.black),
                ],
              ),
            ),
            0.08,
            0.72,
          ),
          const SizedBox(height: 12),
          _cascade(_metaRow(item), 0.16, 0.8),
          if (item.description != null &&
              item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            _cascade(
              _StageDescription(
                text: item.description!.trim(),
                title: item.name,
                ident: widget.ident,
                interactive: isNarrow,
              ),
              0.24,
              0.9,
            ),
          ],
          const SizedBox(height: 22),
          _cascade(_liveBar(), 0.32, 1.0),
          if (widget.nextPlaying != null) ...[
            const SizedBox(height: 14),
            _cascade(_upNext(), 0.4, 1.0),
          ],
        ],
      ],
    );
  }

  Widget _glassPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _channelTag() {
    final channel = widget.channel;
    final catalogLabel = channel.genre != null
        ? '${channel.catalog.name} — ${channel.genre}'
        : channel.catalog.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: widget.ident,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Text(
                channel.addon.name.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Marquee(
          text: catalogLabel.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
            shadows: const [Shadow(blurRadius: 12, color: Colors.black)],
          ),
        ),
      ],
    );
  }

  Widget _metaRow(StremioMeta item) {
    final bits = <Widget>[];
    void add(Widget w) {
      if (bits.isNotEmpty) bits.add(_dot());
      bits.add(w);
    }

    if (item.year != null && item.year!.isNotEmpty) {
      add(Text(item.year!, style: _metaStyle));
    }
    if (item.imdbRating != null) {
      add(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFC107)),
        const SizedBox(width: 4),
        Text(item.imdbRating!.toStringAsFixed(1), style: _metaStyle),
      ]));
    }
    if (item.genres != null && item.genres!.isNotEmpty) {
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
    fontSize: 15,
    fontWeight: FontWeight.w600,
    shadows: [Shadow(blurRadius: 12, color: Colors.black)],
  );

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.40),
            shape: BoxShape.circle,
          ),
        ),
      );

  Widget _liveBar() {
    final np = widget.nowPlaying;
    final progress = widget.displayProgress;
    return Row(
      children: [
        // "Live" indicator uses Home's reserved amber highlight; the progress
        // fill below is white like every Home progress bar (was the channel's
        // blue identity colour for both).
        _LivePip(color: HomeTheme.highlight),
        const SizedBox(width: 9),
        Text('LIVE',
            style: TextStyle(
              color: HomeTheme.highlight,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            )),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          np?.progressText ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _upNext() {
    final n = widget.nextPlaying!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'UP NEXT',
            style: TextStyle(
              color: widget.ident.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              n.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14,
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
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(widget.ident),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          widget.loading ? 'Tuning in…' : 'No broadcast on this channel',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 18,
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
            size: 28, color: Colors.white.withValues(alpha: 0.5)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Now playing hidden — tune in to reveal',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Stage synopsis with "Read more" sheet for mobile.
class _StageDescription extends StatelessWidget {
  final String text;
  final String title;
  final Color ident;
  final bool interactive;

  const _StageDescription({
    required this.text,
    required this.title,
    required this.ident,
    required this.interactive,
  });

  static const _style = TextStyle(
    color: Color(0xC8FFFFFF),
    fontSize: 17,
    height: 1.5,
    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
  );

  @override
  Widget build(BuildContext context) {
    if (!interactive) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: _style,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: _style),
          maxLines: 3,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: c.maxWidth);
        final overflows = tp.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              maxLines: 3,
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

class _LivePip extends StatelessWidget {
  final Color color;
  const _LivePip({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFFFF3B5C),
        shape: BoxShape.circle,
      ),
    );
  }
}

// =========================================================================
// Marquee — auto-scrolling text for overflowing labels.
// =========================================================================

class _Marquee extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _Marquee({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// =========================================================================
// The Dial — a single surfable channel card (premium glass treatment).
// =========================================================================

class _DialCard extends StatefulWidget {
  final StremioTvChannel channel;
  final Color ident;
  final FocusNode focusNode;
  final StremioTvNowPlaying? nowPlaying;
  final double displayProgress;
  final bool hideNowPlaying;
  final bool loading;

  /// TV shows a "press DOWN for options" hint on the focused card; desktop
  /// shows a "right-click" hint on hover. Distinguishes the two.
  final bool isTelevision;
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
    required this.isTelevision,
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

  /// Desktop mouse hover. Mirrors DPAD focus for previewing a channel in the
  /// hero above, and lights the same gold treatment — without stealing the
  /// keyboard focus that DPAD navigation relies on.
  bool _hovered = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
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
    if (isActivateKey(k)) {
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
    // DPAD focus OR desktop hover drive the same "active" visual + hero preview.
    final bool active = _focused || _hovered;

    final card = Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          widget.onFocused();
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
        // Desktop: right-click opens the same quick-actions sheet as long-press.
        onSecondaryTap: widget.onLongPress,
        // Eased focus pop (matches the Home board's poster tiles) instead of
        // an instant Transform snap; the ring/bloom below stay instant, like
        // Home's shadowFx on TV, so only one property animates per move.
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: active ? 1.10 : 1.0,
          child: Container(
            width: 138,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              // Gold focus rim + bloom, matching the Home board's poster tiles
              // (was the per-channel identity colour). Consistent focus colour
              // is what makes the two screens feel like one.
              border: Border.all(
                color: active
                    ? HomeTheme.focusGold
                    : Colors.white.withValues(alpha: 0.06),
                width: active ? 2.5 : 0.5,
              ),
              // The AnimatedScale pop re-rasterizes any blur shadow every frame
              // of the 140ms animation — on every DPAD move — which is what
              // janks surfing on weak TV GPUs. So on TV the focus cue is the
              // gold ring + scale only (no blurred bloom). Phone/desktop, which
              // have the GPU headroom and no rapid DPAD surfing, keep the bloom.
              boxShadow: (active && !widget.isTelevision)
                  ? [
                      BoxShadow(
                        color: HomeTheme.focusGoldDeep.withValues(alpha: 0.45),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 0.667,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster artwork
                  if (poster != null && !widget.hideNowPlaying)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      fadeInDuration:
                          HomeTheme.imageFadeIn(widget.isTelevision),
                      fadeOutDuration:
                          HomeTheme.imageFadeOut(widget.isTelevision),
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
                  // Multi-layer bottom scrim for readability.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment(0, -0.3),
                        colors: [Color(0xEE000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                  // Focused gold tint on top edge (matches the Home poster
                  // focus treatment; the CH badge below keeps its per-channel
                  // identity colour).
                  if (active)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            HomeTheme.focusGold.withValues(alpha: 0.16),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  // Channel number badge.
                  Positioned(
                    top: 9,
                    left: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ident,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        channelNumberLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  if (widget.channel.isFavorite)
                    Positioned(
                      top: 9,
                      right: 9,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star_rounded,
                            size: 14, color: Color(0xFFFFC107)),
                      ),
                    ),
                  // "How to open options" affordance — TV on the focused card
                  // (press DOWN), desktop on hover (right-click). Seated on the
                  // second row (top: 34), clear of the top-row CH badge (whose
                  // width varies with the channel number) and the favourite
                  // star. Never on touch.
                  if (widget.isTelevision && _focused)
                    const Positioned(
                      top: 34,
                      right: 9,
                      child: _DialHintChip(
                        icon: Icons.keyboard_arrow_down_rounded,
                        label: 'OPTIONS',
                      ),
                    )
                  else if (!widget.isTelevision && _hovered)
                    const Positioned(
                      top: 34,
                      right: 9,
                      child: _DialHintChip(
                        icon: Icons.mouse_rounded,
                        label: 'RIGHT-CLICK',
                      ),
                    ),
                  // Title + progress overlay.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(15),
                        ),
                        color: Colors.black.withValues(alpha: 0.55),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.hideNowPlaying
                                ? widget.channel.catalog.name
                                : (item?.name ??
                                    widget.channel.catalog.name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 4,
                              child: Stack(
                                children: [
                                  Container(
                                    color: Colors.white
                                        .withValues(alpha: 0.15),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: widget.displayProgress
                                        .clamp(0.0, 1.0),
                                    child: Container(
                                      // White progress fill to match Home (the
                                      // CH badge keeps the per-channel colour).
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                        borderRadius:
                                            BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // MouseRegion (mouse-only — inert for touch/DPAD) makes desktop hover
    // preview the channel in the hero above, mirroring DPAD focus. It does not
    // request keyboard focus, so it can't hijack remote navigation, and does
    // not auto-scroll (only real focus does), so a passing cursor stays put.
    //
    // RepaintBoundary confines this card's repaints to itself: the focus
    // scale-pop repaints only the card you moved to (not the whole strip), and
    // the tuner's 15s broadcast tick — a bare setState on the whole subtree —
    // can't force neighbours to repaint, only cards whose progress changed.
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) {
          if (!mounted) return;
          if (!_hovered) setState(() => _hovered = true);
          widget.onFocused();
        },
        // onExit can fire in a post-frame callback when the card is removed
        // while the cursor is over it (list recycling on scroll), so guard
        // mounted.
        onExit: (_) {
          if (mounted && _hovered) setState(() => _hovered = false);
        },
        child: card,
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
            ident.withValues(alpha: 0.25),
            const Color(0xFF0A0A12),
            ident.withValues(alpha: 0.08),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: Icon(
          widget.channel.type == 'series'
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          color: Colors.white.withValues(alpha: 0.18),
          size: 32,
        ),
      ),
    );
  }
}

/// Small glassy affordance shown on the active dial card telling the user how
/// to open the quick-actions sheet (DOWN on TV, right-click on desktop).
class _DialHintChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DialHintChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
