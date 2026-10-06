// Composition root: tuner State wires live widget views and legacy sections.

import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sections.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/services/stremio_tv_service.dart';
import 'package:flutter/material.dart';

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

class _StremioTvTunerState extends State<StremioTvTuner>
    implements StremioTvTunerWidgetView {
  final _owners = StremioTvTunerOwners();
  StremioTvTunerSections? _sectionsCache;
  StremioTvTunerSections get _sections =>
      _sectionsCache ??= StremioTvTunerSections(
        StremioTvTunerDependencies(
          view: this,
          owners: _owners,
          context: () => context,
          mounted: () => mounted,
          setState: setState,
          sections: () => _sections,
        ),
      );

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
    _sections.channels.rebuildIndex();
    _owners.activeId.value = widget.channels.isNotEmpty
        ? widget.channels.first.id
        : null;
    _owners.centredId.value = _owners.activeId.value;
    _owners.dialScroll.addListener(_sections.dial.onDialScroll);
    _sections.channels.syncTick();
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
    _sections.channels.rebuildIndex();
    _sections.channels.syncTick();
    if (_owners.activeId.value == null ||
        !widget.channels.any((c) => c.id == _owners.activeId.value)) {
      _owners.activeId.value = widget.channels.isNotEmpty
          ? widget.channels.first.id
          : null;
      _owners.pendingId = _owners.activeId.value;
      _owners.centredId.value = _owners.activeId.value;
      _owners.settle?.cancel();
    }
    // Touch: the displayed list can change under a stationary dial (a search
    // edit re-filters it), which silently remaps index → channel without
    // moving the scroll offset — so no scroll notification would fire to
    // correct the centre. Re-derive it once the new list has laid out.
    if (_sections.dial.touchDial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sections.dial.onDialScroll();
      });
    }
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    _owners.tick?.cancel();
    _owners.settle?.cancel();
    _owners.activeId.dispose();
    _owners.centredId.dispose();
    _owners.pageController.dispose();
    _owners.dialScroll.removeListener(_sections.dial.onDialScroll);
    _owners.dialScroll.dispose();
    super.dispose();
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
        return wide
            ? _sections.layout.buildWide()
            : _sections.layout.buildNarrow();
      },
    );
  }

  @override
  List<StremioTvChannel> get channels => widget.channels;
  @override
  List<StremioTvChannel> get allChannels => widget.allChannels;
  @override
  List<FocusNode> get rowFocusNodes => widget.rowFocusNodes;
  @override
  StremioTvService get service => widget.service;
  @override
  int Function(StremioTvChannel channel) get rotationFor => widget.rotationFor;
  @override
  int get mixSalt => widget.mixSalt;
  @override
  bool get hideNowPlaying => widget.hideNowPlaying;
  @override
  bool get autoRefresh => widget.autoRefresh;
  @override
  bool get isTelevision => widget.isTelevision;
  @override
  Set<String> get loadingChannelIds => widget.loadingChannelIds;
  @override
  void Function(StremioTvChannel channel) get ensureLoaded =>
      widget.ensureLoaded;
  @override
  void Function(StremioTvChannel channel) get onOpenDetail =>
      widget.onOpenDetail;
  @override
  void Function(StremioTvChannel channel) get onPlay => widget.onPlay;
  @override
  double Function(StremioTvChannel channel, double rawProgress)
  get displayProgress => widget.displayProgress;
  @override
  void Function(StremioTvChannel channel) get onToggleFavorite =>
      widget.onToggleFavorite;
  @override
  void Function(StremioTvChannel channel) get onShowGuide => widget.onShowGuide;
  @override
  void Function(StremioTvChannel channel)? get onEditLocal =>
      widget.onEditLocal;
  @override
  void Function(StremioTvChannel channel)? get onExportLocal =>
      widget.onExportLocal;
  @override
  VoidCallback get onFocusSidebar => widget.onFocusSidebar;
  @override
  VoidCallback get onFocusHeader => widget.onFocusHeader;
  @override
  void Function(int realIndex) get onFocusedIndexChanged =>
      widget.onFocusedIndexChanged;

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
  bool _focusRealIndex(int realIndex) =>
      _sections.dial.focusRealIndex(realIndex);
}
