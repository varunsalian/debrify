import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/home/home_theme.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/tv_keys.dart';
import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';
import '../stremio_tv_service.dart';

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
    _activeId.value =
        widget.channels.isNotEmpty ? widget.channels.first.id : null;
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
    final i = (_dialScroll.offset / _dialItemExtent)
        .round()
        .clamp(0, channels.length - 1);
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
      _activeId.value =
          widget.channels.isNotEmpty ? widget.channels.first.id : null;
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
      unawaited(precacheImage(
        ResizeImage.resizeIfNeeded(
          width,
          null,
          CachedNetworkImageProvider(bg),
        ),
        context,
        onError: (_, __) {}, // best-effort warm-up; the Stage has its own error path
      ));
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
    final target = (_dialLeadingPadFor(viewport) +
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
        Widget tile(IconData icon, String label, VoidCallback onTap,
            {Color? tint}) {
          return ListTile(
            leading: Icon(icon, color: tint ?? app.core.tx.withAlpha(0xB3)),
            title: Text(label,
                style: TextStyle(
                    color: app.core.tx, fontWeight: FontWeight.w600)),
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
                child: Row(children: [
                  Container(width: 4, height: 26,
                    decoration: BoxDecoration(
                        color: ident,
                        borderRadius: app.shape.br(2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(channel.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: app.core.tx,
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
                tint: channel.isFavorite ? app.stremioTv.starAccent : null,
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
                    child: Text('All channels',
                        style: TextStyle(
                            color: app.core.tx,
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
    final app = AppThemeScope.of(context);
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
                          value: widget.displayProgress(channel, np.progress)
                              .clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor:
                              app.core.tx.withValues(alpha: 0.14),
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
                  child: Icon(Icons.star_rounded,
                      size: 16, color: app.stremioTv.starAccent),
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
        channel.type == 'series'
            ? Icons.live_tv_rounded
            : Icons.movie_rounded,
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
              final stage = _Stage(
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
              top: BorderSide(
                color: app.stremioTv.hairline,
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
                        horizontal: _dialLeadingPadFor(dialConstraints.maxWidth),
                      ),
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
    final app = AppThemeScope.of(context);
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
      decoration: BoxDecoration(color: app.home.bg),
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
                  // TV) rather than an oversized decode per step. Hidden mode
                  // on TV decodes at 96px with NO gaussian pass (below): the
                  // cover-fit upscale of a tiny decode reads as the same
                  // obscuring blur for free — the hero backdrop's recipe.
                  memCacheWidth: blurArt
                      ? (widget.isTelevision ? 96 : 480)
                      : (widget.isTelevision
                          ? HomeTheme.heroBackdropCacheWidthTv
                          : HomeTheme.heroBackdropCacheWidth),
                  // On TV, snap the swap instead of a fade — deliberately NOT
                  // the shared HomeTheme token (which now fades 150ms on TV
                  // for the small board posters): the Stage swaps to a FRESH
                  // URL on every surf settle, so the memory-cache no-fade
                  // shortcut never applies here, and even a short fade is a
                  // near-full-screen saveLayer per frame on every surf step —
                  // with no placeholder, the old art would also dip to the
                  // page colour mid-fade. The text cascade provides the
                  // transition polish.
                  fadeInDuration: widget.isTelevision
                      ? Duration.zero
                      : const Duration(milliseconds: 500),
                  fadeOutDuration: widget.isTelevision
                      ? Duration.zero
                      : const Duration(milliseconds: 1000),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
                if (blurArt && !widget.isTelevision) {
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
                  app.home.bg.withValues(alpha: 0.97),
                  app.home.bg.withValues(alpha: 0.50),
                  widget.ident.withValues(alpha: 0.06),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Legibility scrims share the page hue (home.bg) so the darkened
          // corners meet the base without a colour seam.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  app.home.bg.withAlpha(0xDD),
                  app.home.bg.withAlpha(0x00),
                ],
              ),
            ),
          ),
          // Side vignette for widescreen depth.
          if (!isNarrow)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    app.home.bg.withAlpha(0x66),
                    app.home.bg.withAlpha(0x00),
                    app.home.bg.withAlpha(0x00),
                    app.home.bg.withAlpha(0x33),
                  ],
                  stops: const [0.0, 0.15, 0.85, 1.0],
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
    final app = AppThemeScope.of(context);
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
                color: app.core.tx,
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
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: app.shape.br(24),
        border: Border.all(
          color: app.onGlass.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: app.onGlass.withValues(alpha: 0.85)),
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                color: app.onGlass.withValues(alpha: 0.85),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _channelTag() {
    final app = AppThemeScope.of(context);
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
                borderRadius: app.shape.br(10),
              ),
              child: Text(
                'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: app.core.tx,
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
                color: app.core.tx.withValues(alpha: 0.08),
                borderRadius: app.shape.br(8),
                border: Border.all(
                  color: app.core.tx.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Text(
                channel.addon.name.toUpperCase(),
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0.50),
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
            color: app.core.tx.withValues(alpha: 0.72),
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
    final app = AppThemeScope.of(context);
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
        Icon(Icons.star_rounded, size: 16, color: app.stremioTv.starAccent),
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

  TextStyle get _metaStyle => TextStyle(
        color: AppThemeScope.of(context).core.tx,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        shadows: const [Shadow(blurRadius: 12, color: Colors.black)],
      );

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.40),
            shape: BoxShape.circle,
          ),
        ),
      );

  Widget _liveBar() {
    final app = AppThemeScope.of(context);
    final np = widget.nowPlaying;
    final progress = widget.displayProgress;
    return Row(
      children: [
        // "Live" indicator uses Home's reserved amber highlight; the progress
        // fill below is white like every Home progress bar (was the channel's
        // blue identity colour for both).
        _LivePip(color: app.home.highlight),
        const SizedBox(width: 9),
        Text('LIVE',
            style: TextStyle(
              color: app.home.highlight,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            )),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: app.shape.br(4),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: app.stremioTv.progressTrack,
                      borderRadius: app.shape.br(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: app.stremioTv.progressFill,
                        borderRadius: app.shape.br(4),
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
            color: app.core.tx.withValues(alpha: 0.65),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _upNext() {
    final app = AppThemeScope.of(context);
    final n = widget.nextPlaying!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: app.stremioTv.surfaceFill,
        borderRadius: app.shape.br(12),
        border: Border.all(
          color: app.stremioTv.hairline,
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
                color: app.core.tx.withValues(alpha: 0.78),
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
    final app = AppThemeScope.of(context);
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
            color: app.core.tx.withValues(alpha: 0.7),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _hiddenState() {
    final app = AppThemeScope.of(context);
    return Row(
      children: [
        Icon(Icons.visibility_off_rounded,
            size: 28, color: app.core.tx.withValues(alpha: 0.5)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Now playing hidden — tune in to reveal',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.78),
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

  TextStyle _styleOf(AppTheme app) => TextStyle(
        color: app.core.tx.withAlpha(0xC8),
        fontSize: 17,
        height: 1.5,
        shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
      );

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final style = _styleOf(app);
    if (!interactive) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
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
              style: style,
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
                        color: app.core.tx.withValues(alpha: 0.95),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.expand_more_rounded,
                        size: 18,
                        color: app.core.tx.withValues(alpha: 0.95)),
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
    // Captured from the calling context — the sheet route is not under this
    // surface's theme boundary.
    final app = AppThemeScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.stremioTv.sheetBg,
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
                color: app.core.tx.withAlpha(0x3D),
                borderRadius: app.shape.br(2),
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
                    borderRadius: app.shape.br(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx,
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
                    color: app.core.tx.withValues(alpha: 0.82),
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

  /// Touch layout: the dial's currently centred channel id — i.e. the channel
  /// the Stage above is showing. That card lights the same gold treatment
  /// D-pad focus and mouse hover light, since it means the same thing.
  ///
  /// The card subscribes itself rather than being rebuilt by an ancestor
  /// ValueListenableBuilder, so a centre change repaints the two cards whose
  /// state actually flipped instead of every mounted card in the strip — a
  /// fling across a long dial crosses a lot of cards. Null on TV / desktop,
  /// where focus and hover already drive this and the cards deliberately don't
  /// depend on the active id at all.
  final ValueListenable<String?>? centredId;

  /// Touch layout: a tap plays outright and must NOT take keyboard focus —
  /// focus would leave a second, contradictory gold ring behind on a card the
  /// Stage isn't showing, and its ensureVisible would fight the snap.
  final bool touchSelect;

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
    required this.centredId,
    required this.touchSelect,
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

  /// Touch layout: this card is the one centred in the dial. Mirrored into
  /// state so only a real flip costs a rebuild.
  bool _centred = false;

  bool get _isCentred =>
      widget.centredId != null && widget.centredId!.value == widget.channel.id;

  @override
  void initState() {
    super.initState();
    _centred = _isCentred;
    widget.centredId?.addListener(_onCentredChanged);
  }

  void _onCentredChanged() {
    final now = _isCentred;
    if (now != _centred && mounted) setState(() => _centred = now);
  }

  @override
  void didUpdateWidget(_DialCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.centredId, widget.centredId)) {
      old.centredId?.removeListener(_onCentredChanged);
      widget.centredId?.addListener(_onCentredChanged);
    }
    // A recycled card can arrive carrying a different channel, so re-derive
    // rather than trusting the mirrored flag. No setState — we're already in a
    // rebuild.
    _centred = _isCentred;
  }

  @override
  void dispose() {
    widget.centredId?.removeListener(_onCentredChanged);
    super.dispose();
  }

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
    final app = AppThemeScope.of(context);
    final item = widget.nowPlaying?.item;
    final poster = item?.poster ?? item?.background;
    final ident = widget.ident;
    // DPAD focus, desktop hover, or (touch) sitting centred in the dial all
    // mean "this is the channel on the Stage" — one visual for all three.
    final bool active = _focused || _hovered || _centred;

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
          if (!widget.touchSelect) widget.focusNode.requestFocus();
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
              borderRadius: app.shape.brImg(16),
              // Gold focus rim + bloom, matching the Home board's poster tiles
              // (was the per-channel identity colour). Consistent focus colour
              // is what makes the two screens feel like one.
              border: Border.all(
                color: active ? app.home.focus : app.stremioTv.hairline,
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
                        color: app.home.focusDeep.withValues(alpha: 0.45),
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
                  // Hidden mode, TV: a 16px decode upscaled by cover-fit is
                  // the obscuring "blur" — no gaussian pass, so the card
                  // costs the same as a plain poster on the weak GPU.
                  else if (poster != null &&
                      widget.hideNowPlaying &&
                      widget.isTelevision)
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      memCacheWidth: 16,
                      fadeInDuration:
                          HomeTheme.imageFadeIn(widget.isTelevision),
                      fadeOutDuration:
                          HomeTheme.imageFadeOut(widget.isTelevision),
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
                            app.home.focus.withValues(alpha: 0.16),
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
                        borderRadius: app.shape.br(8),
                      ),
                      child: Text(
                        channelNumberLabel,
                        style: TextStyle(
                          color: app.core.tx,
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
                        child: Icon(Icons.star_rounded,
                            size: 14, color: app.stremioTv.starAccent),
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
                        color: app.stremioTv.glass,
                        border: Border(
                          top: BorderSide(
                            color: app.onGlass.withValues(alpha: 0.08),
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
                            style: TextStyle(
                              color: app.onGlass,
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: app.shape.br(3),
                            child: SizedBox(
                              height: 4,
                              child: Stack(
                                children: [
                                  Container(
                                    color: app.onGlass
                                        .withValues(alpha: 0.15),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: widget.displayProgress
                                        .clamp(0.0, 1.0),
                                    child: Container(
                                      // White progress fill to match Home (the
                                      // CH badge keeps the per-channel colour).
                                      decoration: BoxDecoration(
                                        color: app.onGlass
                                            .withValues(alpha: 0.9),
                                        borderRadius:
                                            app.shape.br(3),
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
          // In the touch layout the dial's centre is the single selector: an
          // iPad trackpad hovering a card must not light a SECOND gold ring on
          // a channel the Stage isn't showing, nor pull the Stage away from the
          // centred card.
          if (widget.touchSelect) return;
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
    final app = AppThemeScope.of(context);
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
          color: app.core.tx.withValues(alpha: 0.18),
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
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: app.shape.br(6),
        border: Border.all(
          color: app.onGlass.withValues(alpha: 0.16),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: app.onGlass.withValues(alpha: 0.85)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: app.onGlass.withValues(alpha: 0.85),
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
