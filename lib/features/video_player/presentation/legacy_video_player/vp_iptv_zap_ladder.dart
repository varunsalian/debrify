import 'dart:async';
import 'dart:math' as math;
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/utils/iptv_player_paging.dart';

abstract interface class VpIptvZapLadderHost {
  void applyIptvGuideCategory(String? category, List<String>? categories);
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  List<IptvChannel>? get effectiveIptvChannels;
  void ensureIptvZapPagingArmed();
  void installIptvZapWindow(
    VpIptvZapPage page, {
    required bool preservePlayingChannel,
  });
  List<String> get iptvZapCategories;
  String? get iptvZapCategory;
  int get iptvZapCategoryTotal;
  bool get iptvZapPagingActive;
  List<int> get iptvZapPendingInputs;
  bool get iptvZapRequestInFlight;
  int get iptvZapWindowOffset;
  int get iptvZapPageSize;
  void mergeIptvZapPage(VpIptvZapPage page);
  Future<VpIptvZapPage?> requestIptvZapPage({
    required String? category,
    required int offset,
    bool fromEnd = false,
  });
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false});
  bool get mounted;
}

class VpIptvZapLadder {
  VpIptvZapLadder(this._host);
  final VpIptvZapLadderHost _host;

  /// How close to the window's edge counts as "about to need what's next".
  static const int kIptvZapEdgeMargin = 12;
  bool iptvZapDrainingInputs = false;

  /// The adjacent category, fetched before it is needed so crossing one costs
  /// no more than stepping inside the current one.
  String? iptvZapCachedOriginCategory;
  int iptvZapCachedDirection = 0;
  VpIptvZapPage? iptvZapCachedPage;

  void clearIptvZapBoundaryCache() {
    iptvZapCachedOriginCategory = null;
    iptvZapCachedDirection = 0;
    iptvZapCachedPage = null;
  }

  /// Previous/next channel in guide order.
  void zapIptvChannel(int delta) {
    final channels = _host.effectiveIptvChannels;
    final current = _host.currentIptvChannel;
    if (channels == null || current == null || !current.isLive) return;
    if (!_host.iptvZapPagingActive && channels.length < 2) return;
    final from = _host.currentIptvIndex.clamp(0, channels.length - 1);
    final next = from + delta;

    if (!_host.iptvZapPagingActive) {
      // No paged context: the ring is all there is, so wrap inside it.
      unawaited(
        _host.switchToIptvChannel((next + channels.length) % channels.length),
      );
      // Tuning has already moved the index and the switch ticket, so this arms
      // the ladder around the channel just landed on.
      _host.ensureIptvZapPagingArmed();
      return;
    }

    if (next >= 0 && next < channels.length) {
      unawaited(_host.switchToIptvChannel(next));
      unawaited(prefetchIptvZapPage(delta));
      unawaited(prefetchAdjacentIptvCategory(delta));
      return;
    }

    final firstAbsolute = _host.iptvZapWindowOffset;
    final lastAbsolute = _host.iptvZapWindowOffset + channels.length - 1;
    final hasAnotherPage = delta > 0
        ? lastAbsolute + 1 < _host.iptvZapCategoryTotal
        : firstAbsolute > 0;
    if (hasAnotherPage) {
      // The category continues past the window. Hold the press until the page
      // it needs has landed, then replay it against the grown ring.
      queuePendingIptvZapInput(delta);
      unawaited(prefetchIptvZapPage(delta));
      return;
    }

    if (consumeCachedAdjacentIptvCategory(delta)) return;
    unawaited(requestAdjacentIptvCategory(delta));
  }

  /// Pull in the next page of the current category once zapping gets near the
  /// window's edge.
  Future<void> prefetchIptvZapPage(int delta) async {
    if (!_host.iptvZapPagingActive || _host.iptvZapRequestInFlight) return;
    final channels = _host.effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    final firstAbsolute = _host.iptvZapWindowOffset;
    final lastAbsolute = firstAbsolute + channels.length - 1;
    final shouldLoad = delta > 0
        ? lastAbsolute + 1 < _host.iptvZapCategoryTotal &&
              _host.currentIptvIndex >= channels.length - kIptvZapEdgeMargin
        : firstAbsolute > 0 && _host.currentIptvIndex < kIptvZapEdgeMargin;
    if (!shouldLoad) return;

    final page = await _host.requestIptvZapPage(
      category: _host.iptvZapCategory,
      offset: delta > 0
          ? lastAbsolute + 1
          : math.max(0, firstAbsolute - _host.iptvZapPageSize),
    );
    if (!_host.mounted || page == null) return;
    _host.mergeIptvZapPage(page);
    drainPendingIptvZapInputs();
  }

  String? adjacentIptvCategory(int delta, int attempt) =>
      iptvAdjacentZapCategory(
        categories: _host.iptvZapCategories,
        current: _host.iptvZapCategory,
        delta: delta,
        attempt: attempt,
      );

  Future<void> prefetchAdjacentIptvCategory(
    int delta, {
    int attempt = 1,
  }) async {
    // A cached page only answers the direction it was fetched for; turning
    // around makes it the wrong end of the wrong category.
    if (iptvZapCachedPage != null && iptvZapCachedDirection != delta) {
      clearIptvZapBoundaryCache();
    }
    if (!_host.iptvZapPagingActive ||
        _host.iptvZapRequestInFlight ||
        _host.iptvZapCategory == null ||
        iptvZapCachedPage != null) {
      return;
    }
    final channels = _host.effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    final nearBoundary = delta > 0
        ? _host.iptvZapWindowOffset + channels.length >=
                  _host.iptvZapCategoryTotal &&
              _host.currentIptvIndex >= channels.length - kIptvZapEdgeMargin
        : _host.iptvZapWindowOffset == 0 &&
              _host.currentIptvIndex < kIptvZapEdgeMargin;
    if (!nearBoundary) return;

    final target = adjacentIptvCategory(delta, attempt);
    if (target == null) return;
    final origin = _host.iptvZapCategory;
    final page = await _host.requestIptvZapPage(
      category: target,
      offset: 0,
      fromEnd: delta < 0,
    );
    if (!_host.mounted || page == null) return;
    // Zapping moved on while this loaded; it is no longer the next category.
    if (origin != _host.iptvZapCategory) return;
    if (page.channels.isEmpty) {
      await prefetchAdjacentIptvCategory(delta, attempt: attempt + 1);
      return;
    }
    iptvZapCachedOriginCategory = origin;
    iptvZapCachedDirection = delta;
    iptvZapCachedPage = page;
    drainPendingIptvZapInputs();
  }

  /// Cross into the prefetched category with no round trip. Returns false when
  /// nothing usable was cached, leaving the caller to fetch.
  bool consumeCachedAdjacentIptvCategory(int delta) {
    final cached = iptvZapCachedPage;
    if (cached == null ||
        cached.channels.isEmpty ||
        iptvZapCachedOriginCategory != _host.iptvZapCategory ||
        iptvZapCachedDirection != delta) {
      return false;
    }
    clearIptvZapBoundaryCache();
    enterIptvZapCategory(cached, delta);
    unawaited(prefetchAdjacentIptvCategory(delta));
    return true;
  }

  /// Adopt [page] as the ring and tune the channel the zap was heading for:
  /// going forwards that is the new category's first channel, going backwards
  /// its last.
  void enterIptvZapCategory(VpIptvZapPage page, int delta) {
    _host.installIptvZapWindow(page, preservePlayingChannel: false);
    unawaited(
      _host.switchToIptvChannel(delta > 0 ? 0 : page.channels.length - 1),
    );
    // After the tune, not before: the switch anchors the guide to the tuned
    // channel's own group, and the response's category is the more accurate
    // of the two (it can be the null of an uncategorized wrap, which no
    // channel's group expresses).
    _host.applyIptvGuideCategory(
      page.category,
      page.categories.isEmpty ? null : page.categories,
    );
    unawaited(prefetchIptvZapPage(delta));
  }

  /// The category ran out. Load the adjacent one, skipping any that come back
  /// empty, and give up once every category has been tried.
  Future<void> requestAdjacentIptvCategory(int delta, {int attempt = 1}) async {
    if (_host.iptvZapRequestInFlight) {
      queuePendingIptvZapInput(delta);
      return;
    }
    final hasCategories = _host.iptvZapCategories.any((c) => c.isNotEmpty);
    if (_host.iptvZapCategory == null || !hasCategories) {
      // An uncategorized/"All" context has no category boundary to cross:
      // wrap by paging the opposite end of the same result set.
      final page = await _host.requestIptvZapPage(
        category: null,
        offset: 0,
        fromEnd: delta < 0,
      );
      if (!_host.mounted || page == null || page.channels.isEmpty) {
        // Nothing came back to zap into, so nothing will drain these either.
        _host.iptvZapPendingInputs.clear();
        return;
      }
      enterIptvZapCategory(page, delta);
      drainPendingIptvZapInputs();
      return;
    }

    // Null once the walk has been all the way round — every category was
    // empty, so nothing will ever drain the queued presses.
    final target = adjacentIptvCategory(delta, attempt);
    if (target == null) {
      _host.iptvZapPendingInputs.clear();
      return;
    }
    final page = await _host.requestIptvZapPage(
      category: target,
      offset: 0,
      fromEnd: delta < 0,
    );
    if (!_host.mounted || page == null) return;
    if (page.channels.isEmpty) {
      await requestAdjacentIptvCategory(delta, attempt: attempt + 1);
      return;
    }
    enterIptvZapCategory(page, delta);
    unawaited(prefetchAdjacentIptvCategory(delta));
    drainPendingIptvZapInputs();
  }

  void queuePendingIptvZapInput(int delta) {
    if (_host.iptvZapPendingInputs.length >= 24) return;
    _host.iptvZapPendingInputs.add(delta >= 0 ? 1 : -1);
  }

  void drainPendingIptvZapInputs() {
    if (iptvZapDrainingInputs) return;
    iptvZapDrainingInputs = true;
    try {
      while (_host.iptvZapPendingInputs.isNotEmpty) {
        final queued = _host.iptvZapPendingInputs.length;
        zapIptvChannel(_host.iptvZapPendingInputs.removeAt(0));
        // Another round trip started: the rest drain when it lands.
        if (_host.iptvZapRequestInFlight) break;
        // The press went straight back on the queue without starting one, so
        // nothing will arrive to move it along — stop instead of spinning.
        if (_host.iptvZapPendingInputs.length >= queued) break;
      }
    } finally {
      iptvZapDrainingInputs = false;
    }
  }
}
