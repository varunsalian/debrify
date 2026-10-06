import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';

class StremioTvTunerChannels {
  final StremioTvTunerDependencies _deps;
  StremioTvTunerChannels(this._deps);
  StremioTvTunerWidgetView get widget => _deps.view;
  StremioTvTunerOwners get _owners => _deps.owners;

  /// Start/stop the 15s live-broadcast tick per the Auto-refresh setting.
  void syncTick() {
    if (widget.autoRefresh) {
      _owners.tick ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_deps.mounted()) return;
        // Skip the sweep while a pushed route (detail screen, player) or a
        // modal sheet covers the tuner — the page stays mounted under it, and
        // rebuilding every visible card 4×/minute behind an overlay is pure
        // waste on a weak TV. The first tick after it's current again
        // catches the progress bars up.
        final route = ModalRoute.of(_deps.context());
        if (route != null && !route.isCurrent) return;
        _deps.setState(() {});
      });
    } else {
      _owners.tick?.cancel();
      _owners.tick = null;
    }
  }

  void rebuildIndex() {
    // First-wins on duplicate ids (the addon service allows the same addon
    // installed twice with different config, which yields duplicate channel
    // ids) so the map agrees with every indexWhere fallback in this file.
    final map = <String, int>{};
    for (var i = 0; i < widget.allChannels.length; i++) {
      map.putIfAbsent(widget.allChannels[i].id, () => i);
    }
    _owners.indexById = map;
  }

  // --- Channel ident ------------------------------------------------------

  Color identFor(StremioTvChannel c) {
    // The ramp's LENGTH is part of the contract: the id hashes modulo it, so a
    // theme with a shorter ramp still yields a stable per-channel tone.
    final idents = AppThemeScope.of(_deps.context()).stremioTv.channelIdent;
    return idents[c.id.hashCode.abs() % idents.length];
  }

  StremioTvNowPlaying? nowPlaying(StremioTvChannel c) =>
      widget.service.getNowPlaying(
        c,
        rotationMinutes: widget.rotationFor(c),
        salt: widget.mixSalt,
      );

  StremioTvNowPlaying? nextPlaying(StremioTvChannel c) =>
      widget.service.getNextPlaying(
        c,
        rotationMinutes: widget.rotationFor(c),
        salt: widget.mixSalt,
      );

  double displayProgress(StremioTvChannel c, StremioTvNowPlaying? np) =>
      np == null ? 0.0 : widget.displayProgress(c, np.progress);

  int _realIndex(StremioTvChannel c) {
    final all = widget.allChannels;
    final i = _owners.indexById[c.id];
    // Validate the cached index against the live list: the screen mutates its
    // channel/node lists *in place* when an empty channel is removed, so the
    // cache can be stale for the microtask window before the next rebuild
    // refreshes it. On a miss, re-sync the cache and answer from it (one
    // pass, and the same first-wins semantics as the warm path).
    if (i != null && i < all.length && all[i].id == c.id) return i;
    rebuildIndex();
    return _owners.indexById[c.id] ?? -1;
  }

  FocusNode? nodeFor(StremioTvChannel c) {
    final i = _realIndex(c);
    return (i >= 0 && i < widget.rowFocusNodes.length)
        ? widget.rowFocusNodes[i]
        : null;
  }

  void setActive(StremioTvChannel c) {
    if (_owners.pendingId == c.id) return;
    _owners.pendingId = c.id;
    final ri = _realIndex(c);
    if (ri >= 0) widget.onFocusedIndexChanged(ri);
    _owners.settle?.cancel();
    _owners.settle = Timer(const Duration(milliseconds: 180), () {
      if (!_deps.mounted()) return;
      final id = _owners.pendingId;
      if (id == null || _owners.activeId.value == id) return;
      // The channel can be removed from the list during the 180ms settle
      // (empty lazy-load). Don't write a dead id: _channelById would render
      // channels.first while state pointed at the ghost until the next
      // rebuild reset it.
      if (!widget.channels.any((c) => c.id == id)) return;
      // Only the Stage's ValueListenableBuilder rebuilds — the dial cards
      // don't depend on the active id, so surfing never re-runs them...
      _owners.activeId.value = id;
      // ...except when Auto-refresh is off: with the 15s tick cancelled a
      // surf settle is the only moment left to re-evaluate the dial cards'
      // now-playing/progress, otherwise they'd drift out of sync with the
      // Stage after a slot rollover. One cheap rebuild per settle.
      if (!widget.autoRefresh) _deps.setState(() {});
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
    if (!_deps.mounted()) return;
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
      final item = nowPlaying(channels[n])?.item;
      final bg = item?.background ?? item?.poster;
      if (bg == null || bg.isEmpty) continue;
      unawaited(
        precacheImage(
          ResizeImage.resizeIfNeeded(
            width,
            null,
            CachedNetworkImageProvider(bg),
          ),
          _deps.context(),
          onError:
              (
                _,
                __,
              ) {}, // best-effort warm-up; the Stage has its own error path
        ),
      );
    }
  }

  StremioTvChannel? channelById(String? id) {
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
  void surf(StremioTvChannel channel, int buildIndex, int delta) {
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
    nodeFor(live[target])?.requestFocus();
  }
}
