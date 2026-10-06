import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_dial_card.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/services/stremio_tv_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Imperative handle the screen uses to move D-pad focus onto a dial card
/// *reliably*, even when that card has been recycled off-screen by the dial's
/// [ListView.builder].
///
/// A bare `FocusNode.requestFocus()` on a node whose card isn't currently
/// mounted is a silent no-op — that is the root of two long-tail TV bugs:
/// focus escaping the dial to the header search box on a long channel hold, and
/// then down-arrow never bringing it back. This routes those "jump" focus moves
/// through the tuner so the target card is scrolled into view (and thus built)
/// before it is focused.
class StremioTvTunerController {
  _StremioTvTunerState? _state;

  void _bind(_StremioTvTunerState state) => _state = state;
  void _unbind(_StremioTvTunerState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Move focus to the channel at [realIndex] (an index into the screen's full
  /// `allChannels`/`rowFocusNodes` list), scrolling the dial so its card is
  /// mounted first. Returns false when the tuner is absent, in its narrow
  /// (phone) layout, or the channel isn't in the displayed dial — the caller
  /// should then fall back to a best-effort direct focus.
  bool focusRealIndex(int realIndex) =>
      _state?._focusRealIndex(realIndex) ?? false;
}

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

  /// Optional imperative handle so the screen can reliably move focus onto a
  /// dial card (scrolling it into view first). See [StremioTvTunerController].
  final StremioTvTunerController? controller;

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
    this.controller,
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

  /// Channel id currently CENTRED in the dial (touch layout only). Kept apart
  /// from [_activeId] because the centre ring has to track the finger frame by
  /// frame while the expensive Stage swap stays behind [_setActive]'s settle
  /// debounce.
  final ValueNotifier<String?> _centredId = ValueNotifier<String?>(null);

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

  /// True when the wide layout is being driven by a finger — i.e. a tablet.
  ///
  /// The Stage follows [_activeId], which in the wide layout is only ever
  /// written by D-pad focus or desktop mouse hover. A touch tablet has
  /// neither, so without this the hero stays pinned to the first channel
  /// forever. In this mode the dial itself becomes the selector: it centre-
  /// snaps, and whichever card sits in the middle drives the Stage.
  ///
  /// TV keeps focus-driven surfing and desktop keeps hover preview, untouched.
  bool get _touchDial =>
      !widget.isTelevision &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
    _rebuildIndex();
    _activeId.value = widget.channels.isNotEmpty
        ? widget.channels.first.id
        : null;
    _centredId.value = _activeId.value;
    _dialScroll.addListener(_onDialScroll);
    _syncTick();
  }

  /// Touch layout: adopt the card nearest the dial's centre as we scroll. The
  /// centre-padding below makes `offset == index * extent` the exact centring
  /// offset, so the lookup is a divide instead of a hit test.
  void _onDialScroll() {
    if (!_touchDial || !_dialScroll.hasClients) return;
    final channels = widget.channels;
    if (channels.isEmpty) return;
    final i = (_dialScroll.offset / _dialItemExtent).round().clamp(
      0,
      channels.length - 1,
    );
    final c = channels[i];
    // The ring follows immediately; the Stage swap stays debounced (and
    // neighbour backdrops pre-warmed) by _setActive's settle timer.
    if (_centredId.value != c.id) _centredId.value = c.id;
    _setActive(c);
  }

  /// Settle the dial onto the nearest card once a touch scroll comes to rest.
  ///
  /// Snapping at the END of the fling rather than clamping each card as it
  /// passes is what lets a flick coast across a long channel list; a per-item
  /// snap would make a 200-channel dial feel like dragging through treacle.
  /// The animation lands exactly on target, so the ScrollEndNotification it
  /// emits in turn is a no-op and this can't loop.
  void _snapDial() {
    if (!_touchDial || !_dialScroll.hasClients) return;
    if (widget.channels.isEmpty) return;
    final pos = _dialScroll.position;
    final target = ((pos.pixels / _dialItemExtent).round() * _dialItemExtent)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 0.5) return;
    _dialScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Start/stop the 15s live-broadcast tick per the Auto-refresh setting.
  void _syncTick() {
    if (widget.autoRefresh) {
      _tick ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (!mounted) return;
        // Skip the sweep while a pushed route (detail screen, player) or a
        // modal sheet covers the tuner — the page stays mounted under it, and
        // rebuilding every visible card 4×/minute behind an overlay is pure
        // waste on a weak TV. The first tick after it's current again
        // catches the progress bars up.
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
        setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void didUpdateWidget(StremioTvTuner old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller?._unbind(this);
      widget.controller?._bind(this);
    }
    // NB: always rebuild — the host mutates its channel list IN PLACE (empty-
    // channel removal), so old.channels is the same object as widget.channels
    // and an identical()/length guard can never detect the change. The O(n)
    // walk is microseconds; correctness wins.
    _rebuildIndex();
    _syncTick();
    if (_activeId.value == null ||
        !widget.channels.any((c) => c.id == _activeId.value)) {
      _activeId.value = widget.channels.isNotEmpty
          ? widget.channels.first.id
          : null;
      _pendingId = _activeId.value;
      _centredId.value = _activeId.value;
      _settle?.cancel();
    }
    // Touch: the displayed list can change under a stationary dial (a search
    // edit re-filters it), which silently remaps index → channel without
    // moving the scroll offset — so no scroll notification would fire to
    // correct the centre. Re-derive it once the new list has laid out.
    if (_touchDial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onDialScroll();
      });
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
    widget.controller?._unbind(this);
    _tick?.cancel();
    _settle?.cancel();
    _activeId.dispose();
    _centredId.dispose();
    _pageController.dispose();
    _dialScroll.removeListener(_onDialScroll);
    _dialScroll.dispose();
    super.dispose();
  }

  // --- Channel ident ------------------------------------------------------

  Color _identFor(StremioTvChannel c) {
    // The ramp's LENGTH is part of the contract: the id hashes modulo it, so a
    // theme with a shorter ramp still yields a stable per-channel tone.
    final idents = AppThemeScope.of(context).stremioTv.channelIdent;
    return idents[c.id.hashCode.abs() % idents.length];
  }

  StremioTvNowPlaying? _nowPlaying(StremioTvChannel c) =>
      widget.service.getNowPlaying(
        c,
        rotationMinutes: widget.rotationFor(c),
        salt: widget.mixSalt,
      );

  StremioTvNowPlaying? _nextPlaying(StremioTvChannel c) =>
      widget.service.getNextPlaying(
        c,
        rotationMinutes: widget.rotationFor(c),
        salt: widget.mixSalt,
      );

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
      _precacheNeighborBackdrops(id);
    });
  }

  /// Warm the image cache with the ADJACENT channels' Stage backdrops after a
  /// surf settle, so the next left/right step swaps to an already-decoded
  /// image instead of paying a full-screen decode mid-surf (the visible jank
  /// when ranging across many channels). ±1 only: the TV image cache is
  /// capped at 40 MB (~15 backdrops), so a wider net would evict more than it
  /// warms. Decode params mirror the Stage's exactly — a mismatched width
  /// would decode a SECOND copy instead of hitting the same cache entry.
  void _precacheNeighborBackdrops(String id) {
    if (!mounted) return;
    final channels = widget.channels;
    final idx = channels.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final width = widget.hideNowPlaying
        // Must mirror the Stage's hidden-mode decode exactly (96 on TV — the
        // no-gaussian tiny decode) or the warm-up decodes a second copy.
        ? (widget.isTelevision ? 96 : 480)
        : (widget.isTelevision
              ? HomeTheme.heroBackdropCacheWidthTv
              : HomeTheme.heroBackdropCacheWidth);
    for (final n in [idx - 1, idx + 1]) {
      if (n < 0 || n >= channels.length) continue;
      final item = _nowPlaying(channels[n])?.item;
      final bg = item?.background ?? item?.poster;
      if (bg == null || bg.isEmpty) continue;
      unawaited(
        precacheImage(
          ResizeImage.resizeIfNeeded(
            width,
            null,
            CachedNetworkImageProvider(bg),
          ),
          context,
          onError:
              (
                _,
                __,
              ) {}, // best-effort warm-up; the Stage has its own error path
        ),
      );
    }
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
    final cur =
        (buildIndex >= 0 &&
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

  // --- Reliable focus jumps (header handoff / focus rescue) --------------

  /// Total horizontal extent of one dial card: [_DialCard]'s 138px Container
  /// plus its 8px symmetric margin. Used to estimate a scroll offset that will
  /// build an off-screen card so it can actually receive focus.
  static const double _dialItemExtent = 138.0 + 16.0;

  /// Leading horizontal padding of the dial [ListView] on TV / desktop.
  static const double _dialLeadingPad = 32.0;

  /// Leading padding of the dial for a [viewport]-wide slot. Touch centres the
  /// strip — half a viewport minus half a card at each end — so the first and
  /// last channels can both reach the middle, and so `offset == index * extent`
  /// is exactly the centring offset (which both [_onDialScroll] and [_snapDial]
  /// rely on). TV / desktop keep the flush-left shelf.
  double _dialLeadingPadFor(double viewport) => _touchDial
      ? ((viewport - _dialItemExtent) / 2).clamp(0.0, double.infinity)
      : _dialLeadingPad;

  /// Move D-pad focus to the channel at [realIndex] in [StremioTvTuner.allChannels],
  /// scrolling the dial so its card is mounted first. Returns false when the
  /// channel isn't in the displayed dial or we're in the narrow (phone) layout
  /// with no dial to scroll — the caller falls back to a direct focus request.
  ///
  /// This is the reliable counterpart to a bare `requestFocus`: on a long
  /// channel hold the previously focused card can be recycled off-screen, and
  /// focusing a recycled ListView child silently does nothing. Both the "focus
  /// jumped to search" escape and the "down-arrow won't return to channels"
  /// trap trace back to that no-op.
  bool _focusRealIndex(int realIndex) {
    if (!mounted) return false;
    if (realIndex < 0 ||
        realIndex >= widget.allChannels.length ||
        realIndex >= widget.rowFocusNodes.length) {
      return false;
    }
    final channel = widget.allChannels[realIndex];
    final dialIndex = widget.channels.indexWhere((c) => c.id == channel.id);
    if (dialIndex < 0) return false; // not currently displayed
    final node = widget.rowFocusNodes[realIndex];
    // Narrow layout has no horizontal dial to scroll; leave it to the caller.
    if (!_dialScroll.hasClients) {
      node.requestFocus();
      return true;
    }
    // Card already mounted (on-screen): focus immediately, no scroll jolt.
    if (node.context != null) {
      node.requestFocus();
      return true;
    }
    // Off-screen: bring the card into view so it builds, then focus once its
    // Focus widget has attached (the card's own onFocusChange re-centres it).
    _scrollDialToIndex(dialIndex);
    _focusWhenAttached(node, 0);
    return true;
  }

  void _scrollDialToIndex(int dialIndex) {
    if (!_dialScroll.hasClients) return;
    final pos = _dialScroll.position;
    final viewport = pos.viewportDimension;
    final target =
        (_dialLeadingPadFor(viewport) +
                dialIndex * _dialItemExtent +
                _dialItemExtent / 2 -
                viewport / 2)
            .clamp(0.0, pos.maxScrollExtent);
    _dialScroll.jumpTo(target);
  }

  /// Focus [node] on the next frame(s), once the scrolled-in card has built and
  /// its FocusNode is attached. Bounded retries cover the rare case where one
  /// frame isn't enough for the ListView to lay the card out.
  void _focusWhenAttached(FocusNode node, int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The host can cull an empty channel and dispose its node within these
      // few frames; requesting focus on a disposed node throws, so bail if it's
      // no longer one of the live row nodes.
      if (!widget.rowFocusNodes.contains(node)) return;
      if (node.context != null) {
        node.requestFocus();
      } else if (attempt < 3) {
        _focusWhenAttached(node, attempt + 1);
      }
    });
  }

  // --- Long-press quick actions ------------------------------------------

  Future<void> _openActions(StremioTvChannel channel) async {
    final ident = _identFor(channel);
    // Read from THIS context, not the sheet's: the sheet route sits above the
    // surface's theme boundary, so a captured value is what keeps it in step.
    final app = AppThemeScope.of(context);
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.stremioTv.sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        Widget tile(
          IconData icon,
          String label,
          VoidCallback onTap, {
          Color? tint,
        }) {
          return ListTile(
            leading: Icon(icon, color: tint ?? app.core.tx.withAlpha(0xB3)),
            title: Text(
              label,
              style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w600),
            ),
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
                  color: app.core.tx.withAlpha(0x3D),
                  borderRadius: app.shape.br(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 26,
                      decoration: BoxDecoration(
                        color: ident,
                        borderRadius: app.shape.br(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        channel.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: app.core.tx,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              tile(
                Icons.play_arrow_rounded,
                'Play this channel now',
                () => widget.onPlay(channel),
                tint: ident,
              ),
              if (!widget.hideNowPlaying)
                tile(
                  Icons.info_outline_rounded,
                  'View details',
                  () => widget.onOpenDetail(channel),
                ),
              if (!widget.hideNowPlaying)
                tile(
                  Icons.live_tv_rounded,
                  'Channel guide',
                  () => widget.onShowGuide(channel),
                ),
              tile(
                channel.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                channel.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                () => widget.onToggleFavorite(channel),
                tint: channel.isFavorite ? app.stremioTv.starAccent : null,
              ),
              if (channel.isLocal && widget.onEditLocal != null)
                tile(
                  Icons.edit_rounded,
                  'Edit local catalog',
                  () => widget.onEditLocal!(channel),
                ),
              if (channel.isLocal && widget.onExportLocal != null)
                tile(
                  Icons.copy_all_rounded,
                  'Copy catalog JSON',
                  () => widget.onExportLocal!(channel),
                ),
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
    final app = AppThemeScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.stremioTv.sheetBg,
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
                    color: app.core.tx.withAlpha(0x3D),
                    borderRadius: app.shape.br(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'All channels',
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
    final app = AppThemeScope.of(context);
    final ident = _identFor(channel);
    final np = widget.hideNowPlaying ? null : _nowPlaying(channel);
    final poster = np?.item.poster;
    final active = channel.id == _activeId.value;
    return Material(
      color: active ? ident.withValues(alpha: 0.16) : Colors.transparent,
      child: InkWell(
        onTap: () {
          final idx = widget.channels.indexWhere((c) => c.id == channel.id);
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: ident,
                  borderRadius: app.shape.br(6),
                ),
                child: Text(
                  'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.core.tx,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: app.shape.brImg(6),
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
                      style: TextStyle(
                        color: app.core.tx,
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
                        color: app.core.tx.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                    if (np != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: app.shape.br(2),
                        child: LinearProgressIndicator(
                          value: widget
                              .displayProgress(channel, np.progress)
                              .clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: app.core.tx.withValues(alpha: 0.14),
                          valueColor: AlwaysStoppedAnimation(ident),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (channel.isFavorite)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: app.stremioTv.starAccent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listThumbFallback(Color ident, StremioTvChannel channel) {
    final app = AppThemeScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ident.withValues(alpha: 0.35), app.home.posterPlaceholder],
        ),
      ),
      child: Icon(
        channel.type == 'series' ? Icons.live_tv_rounded : Icons.movie_rounded,
        size: 18,
        color: app.core.tx.withValues(alpha: 0.3),
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
    final app = AppThemeScope.of(context);
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
              final stage = StremioTvTunerStage(
                channel: active,
                ident: _identFor(active),
                nowPlaying: np,
                nextPlaying: _nextPlaying(active),
                displayProgress: _displayProgress(active, np),
                hideNowPlaying: widget.hideNowPlaying,
                isTelevision: widget.isTelevision,
                loading: widget.loadingChannelIds.contains(active.id),
              );
              // Touch: the hero is the biggest target on screen and, until
              // now, the only inert one — tapping it plays what it is showing,
              // long-press opens the same quick actions as a dial card. TV and
              // desktop keep playing from the dial (OK / click), where focus
              // already lives.
              if (!_touchDial) return stage;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onPlay(active),
                onLongPress: () => _openActions(active),
                child: stage,
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
                app.home.bg.withValues(alpha: 0.0),
                app.home.bg.withValues(alpha: 0.72),
              ],
            ),
            border: Border(
              top: BorderSide(color: app.stremioTv.hairline, width: 0.5),
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
                // Touch: settle onto the nearest card when the fling stops, so
                // the dial always comes to rest on the channel the Stage above
                // is showing.
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.depth == 0 && n is ScrollEndNotification) _snapDial();
                    return false;
                  },
                  // The centre padding (touch only) is a function of the dial's
                  // own width, so it has to be measured here rather than from
                  // the page constraints.
                  child: LayoutBuilder(
                    builder: (context, dialConstraints) => ListView.builder(
                      controller: _dialScroll,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(
                        horizontal: _dialLeadingPadFor(
                          dialConstraints.maxWidth,
                        ),
                      ),
                      itemCount: dial.length,
                      itemBuilder: (context, i) {
                        final channel = dial[i];
                        widget.ensureLoaded(channel);
                        final node = _nodeFor(channel)!;
                        final np = _nowPlaying(channel);
                        return StremioTvTunerDialCard(
                          key: ValueKey(channel.id),
                          channel: channel,
                          ident: _identFor(channel),
                          focusNode: node,
                          nowPlaying: np,
                          displayProgress: _displayProgress(channel, np),
                          hideNowPlaying: widget.hideNowPlaying,
                          loading: widget.loadingChannelIds.contains(
                            channel.id,
                          ),
                          isTelevision: widget.isTelevision,
                          // Touch only: the centred card wears the gold ring so
                          // the selection is visible before you scroll. Null on
                          // TV / desktop keeps the cards independent of the
                          // active id, so surfing never re-runs them.
                          centredId: _touchDial ? _centredId : null,
                          touchSelect: _touchDial,
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
          child: StremioTvTunerStage(
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
