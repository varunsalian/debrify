import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sections.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

class StremioTvTunerDial {
  final StremioTvTunerDependencies _deps;
  StremioTvTunerDial(this._deps);
  StremioTvTunerWidgetView get widget => _deps.view;
  StremioTvTunerOwners get _owners => _deps.owners;
  StremioTvTunerSections get _sections => _deps.sections();

  /// True when the wide layout is being driven by a finger — i.e. a tablet.
  ///
  /// The Stage follows [_activeId], which in the wide layout is only ever
  /// written by D-pad focus or desktop mouse hover. A touch tablet has
  /// neither, so without this the hero stays pinned to the first channel
  /// forever. In this mode the dial itself becomes the selector: it centre-
  /// snaps, and whichever card sits in the middle drives the Stage.
  ///
  /// TV keeps focus-driven surfing and desktop keeps hover preview, untouched.
  bool get touchDial =>
      !widget.isTelevision &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Touch layout: adopt the card nearest the dial's centre as we scroll. The
  /// centre-padding below makes `offset == index * extent` the exact centring
  /// offset, so the lookup is a divide instead of a hit test.
  void onDialScroll() {
    if (!touchDial || !_owners.dialScroll.hasClients) return;
    final channels = widget.channels;
    if (channels.isEmpty) return;
    final i = (_owners.dialScroll.offset / _dialItemExtent).round().clamp(
      0,
      channels.length - 1,
    );
    final c = channels[i];
    // The ring follows immediately; the Stage swap stays debounced (and
    // neighbour backdrops pre-warmed) by _setActive's settle timer.
    if (_owners.centredId.value != c.id) _owners.centredId.value = c.id;
    _sections.channels.setActive(c);
  }

  /// Settle the dial onto the nearest card once a touch scroll comes to rest.
  ///
  /// Snapping at the END of the fling rather than clamping each card as it
  /// passes is what lets a flick coast across a long channel list; a per-item
  /// snap would make a 200-channel dial feel like dragging through treacle.
  /// The animation lands exactly on target, so the ScrollEndNotification it
  /// emits in turn is a no-op and this can't loop.
  void snapDial() {
    if (!touchDial || !_owners.dialScroll.hasClients) return;
    if (widget.channels.isEmpty) return;
    final pos = _owners.dialScroll.position;
    final target = ((pos.pixels / _dialItemExtent).round() * _dialItemExtent)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 0.5) return;
    _owners.dialScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
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
  double dialLeadingPadFor(double viewport) => touchDial
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
  bool focusRealIndex(int realIndex) {
    if (!_deps.mounted()) return false;
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
    if (!_owners.dialScroll.hasClients) {
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
    if (!_owners.dialScroll.hasClients) return;
    final pos = _owners.dialScroll.position;
    final viewport = pos.viewportDimension;
    final target =
        (dialLeadingPadFor(viewport) +
                dialIndex * _dialItemExtent +
                _dialItemExtent / 2 -
                viewport / 2)
            .clamp(0.0, pos.maxScrollExtent);
    _owners.dialScroll.jumpTo(target);
  }

  /// Focus [node] on the next frame(s), once the scrolled-in card has built and
  /// its FocusNode is attached. Bounded retries cover the rare case where one
  /// frame isn't enough for the ListView to lay the card out.
  void _focusWhenAttached(FocusNode node, int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
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
}
