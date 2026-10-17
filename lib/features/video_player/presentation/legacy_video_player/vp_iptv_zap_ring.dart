import 'dart:async';
import 'dart:math' as math;
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/utils/iptv_player_paging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract interface class VpIptvZapRingHost {
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories});
  void clearIptvZapBoundaryCache();
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  set currentIptvIndex(int v);
  List<IptvChannel>? get effectiveIptvChannels;
  set iptvChannelsOverride(List<IptvChannel>? v);
  int get iptvGuideContextGeneration;
  IptvGuideContext? get iptvGuideContextOverride;
  int get iptvSwitchTicket;
  set iptvZapCategories(List<String> v);
  String? get iptvZapCategory;
  set iptvZapCategory(String? v);
  set iptvZapCategoryTotal(int v);
  bool get iptvZapPagingActive;
  set iptvZapPagingActive(bool v);
  List<int> get iptvZapPendingInputs;
  bool get iptvZapRequestInFlight;
  set iptvZapRequestInFlight(bool v);
  int get iptvZapWindowOffset;
  set iptvZapWindowOffset(int v);
  int get iptvZapPageSize;
  bool get mounted;
  void setState(VoidCallback fn);
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  get iptvBrowseProvider;
  String? get iptvSourceId;
}

class VpIptvZapRing {
  VpIptvZapRing(this._host);
  final VpIptvZapRingHost _host;

  /// Rebuild the channel ring around [channel] from its own category.
  ///
  /// The native guide does this on every pick (`beginIptvCategoryZapSession`):
  /// the list you navigate afterwards is the channel's category, never the
  /// list you happened to pick from. Without it, choosing a channel out of a
  /// search left the search matches standing in as the entire channel list —
  /// so the guide reopened onto a handful of unrelated channels, and the
  /// category shown alongside them belonged to the previous selection.
  ///
  /// Best effort by design: playback has already started, so a failed or
  /// unhelpful page simply leaves the adopted list in place, which is what
  /// the native fallback does too.
  Future<void> reanchorIptvRingToCategory(
    IptvChannel channel, {
    required int switchTicket,
  }) async {
    final provider = _host.iptvBrowseProvider;
    if (provider == null || !channel.isLive) return;
    if (switchTicket != _host.iptvSwitchTicket) return;
    final category = channel.group?.trim();
    final contextGeneration = _host.iptvGuideContextGeneration;

    Map<String, dynamic>? result;
    try {
      result = await provider({
        'action': 'zapPage',
        'sourceId':
            _host.iptvGuideContextOverride?.sourceId ?? _host.iptvSourceId,
        'contentType': 'live',
        'category': (category == null || category.isEmpty) ? null : category,
        'query': '',
        'anchorUrl': channel.url,
        'anchorName': channel.name,
        'offset': 0,
        // A full page rather than the native player's 200: unlike the native
        // guide this one has no scroll-prefetch to grow a small window, so the
        // ring has to arrive anchored AND whole. Anything past the provider's
        // own maximum is clamped there.
        'limit': _host.iptvZapPageSize,
      });
    } catch (error) {
      debugPrint('Player: IPTV ring re-anchor failed: $error');
      return;
    }
    if (!_host.mounted || result == null) return;
    // A newer zap owns the ring now — installing this page would drop the
    // viewer onto the wrong channel's neighbours.
    if (switchTicket != _host.iptvSwitchTicket) return;
    // The user browsed while this was in flight. Their category is the
    // current intent; this page predates it.
    if (contextGeneration != _host.iptvGuideContextGeneration) return;
    // Last line of defence: whatever else moved, the ring must only ever be
    // rebuilt around the channel that is actually playing.
    final playing = _host.currentIptvChannel;
    if (playing == null ||
        playing.url != channel.url ||
        playing.name != channel.name) {
      return;
    }

    final page = parseIptvZapPage(result);
    if (page == null) return;
    final playingIndex = page.channels.indexWhere(
      (candidate) =>
          candidate.url == channel.url && candidate.name == channel.name,
    );
    // The page has to contain what is playing, or the ring would no longer
    // describe the channel on screen.
    if (playingIndex < 0) return;

    _host.clearIptvZapBoundaryCache();
    _host.setState(() {
      _host.iptvChannelsOverride = page.channels;
      _host.currentIptvIndex = playingIndex;
      // Where this window sits in the category. Zapping past its edge needs
      // both numbers: without them the window's end and the category's end
      // are indistinguishable, and a category larger than one page would
      // cross into the next category partway through.
      _host.iptvZapWindowOffset = page.offset;
      _host.iptvZapCategoryTotal = page.total;
      // Binds every later boundary request to the source this ring came from,
      // however far the guide wanders afterwards.
      iptvZapSourceId =
          page.sourceId ??
          _host.iptvGuideContextOverride?.sourceId ??
          _host.iptvSourceId;
      _host.iptvZapCategory = page.category;
      if (page.categories.isNotEmpty) _host.iptvZapCategories = page.categories;
      _host.iptvZapPagingActive = true;
    });
    _host.anchorIptvGuideCategory(channel, categories: result['categories']);
  }

  /// The source and category the ring belongs to. Kept apart from the guide's
  /// selection on purpose: browsing can move the guide to another source or
  /// category — and leave it there without ever tuning — while the ring keeps
  /// describing what is playing. Asking the guide's source for the ring's
  /// category would fetch a category that source may not even have.
  String? iptvZapSourceId;

  int iptvZapRequestTicket = 0;

  /// Live IPTV with somewhere to zap to — either more than one channel in the
  /// ring, or a paged context that can fetch more.
  bool get canZapIptvChannel =>
      _host.currentIptvChannel?.isLive == true &&
      ((_host.effectiveIptvChannels?.length ?? 0) > 1 ||
          _host.iptvZapPagingActive);

  /// The ring is about to stop being a page of a category. Bumping the request
  /// ticket strands anything in flight: it would otherwise merge a page of the
  /// old category into the new ring at positions that mean nothing there.
  void resetIptvZapPaging() {
    _host.iptvZapPagingActive = false;
    _host.iptvZapWindowOffset = 0;
    _host.iptvZapCategoryTotal = 0;
    iptvZapSourceId = null;
    _host.iptvZapCategory = null;
    iptvZapRequestTicket++;
    _host.iptvZapRequestInFlight = false;
    _host.iptvZapPendingInputs.clear();
    _host.clearIptvZapBoundaryCache();
  }

  /// A re-anchor is out arming the ladder, so a burst of presses can't stack
  /// full-category queries behind it.
  bool iptvZapArmingPaging = false;

  /// Arm the ladder around whatever live channel is playing now.
  ///
  /// The launch bootstrap re-anchors the channel the player opened with, but a
  /// zap landing before that response does moves the switch ticket on and the
  /// response is dropped. Nothing else would re-arm it, so the ladder would sit
  /// inactive and zapping would circle the launch window until the user opened
  /// the guide and retuned. Retrying from the zap itself closes that: the first
  /// press after a lost bootstrap arms the ladder for the channel it landed on.
  void ensureIptvZapPagingArmed() {
    if (_host.iptvZapPagingActive || iptvZapArmingPaging) return;
    if (_host.iptvBrowseProvider == null) return;
    final channel = _host.currentIptvChannel;
    if (channel == null || !channel.isLive) return;
    iptvZapArmingPaging = true;
    unawaited(
      reanchorIptvRingToCategory(
        channel,
        switchTicket: _host.iptvSwitchTicket,
      ).whenComplete(() => iptvZapArmingPaging = false),
    );
  }

  /// One page request at a time, like native: a second in-flight request would
  /// race the first into the ring with no way to order the two.
  Future<VpIptvZapPage?> requestIptvZapPage({
    required String? category,
    required int offset,
    bool fromEnd = false,
  }) async {
    final provider = _host.iptvBrowseProvider;
    if (provider == null || _host.iptvZapRequestInFlight) return null;
    final ticket = ++iptvZapRequestTicket;
    final contextGeneration = _host.iptvGuideContextGeneration;
    _host.iptvZapRequestInFlight = true;

    Map<String, dynamic>? result;
    try {
      result = await provider({
        'action': 'zapPage',
        // The ring's own source, not the guide's — see [_iptvZapSourceId].
        'sourceId':
            iptvZapSourceId ??
            _host.iptvGuideContextOverride?.sourceId ??
            _host.iptvSourceId,
        'contentType': 'live',
        'category': (category == null || category.isEmpty) ? null : category,
        'query': '',
        'offset': offset < 0 ? 0 : offset,
        'limit': _host.iptvZapPageSize,
        'fromEnd': fromEnd,
      });
    } catch (error) {
      debugPrint('Player: IPTV zap page failed: $error');
    }
    // A newer request (or a reset) owns the flag now — leave it to them.
    if (ticket != iptvZapRequestTicket) return null;
    _host.iptvZapRequestInFlight = false;
    if (!_host.mounted || result == null) {
      // Replaying queued presses against a ring that never grew would spin.
      _host.iptvZapPendingInputs.clear();
      return null;
    }
    // The user browsed while this was in flight; their category is the current
    // intent and every queued press belonged to the old one.
    if (contextGeneration != _host.iptvGuideContextGeneration) {
      _host.iptvZapPendingInputs.clear();
      return null;
    }
    return parseIptvZapPage(result);
  }

  VpIptvZapPage? parseIptvZapPage(Map<String, dynamic> result) {
    final raw = result['channels'];
    if (raw is! List) return null;
    final channels = [
      for (final entry in raw.whereType<Map>())
        iptvChannelFromBrowsePayload(Map<String, dynamic>.from(entry)),
    ];
    final rawOffset = result['pageOffset'];
    final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;
    final rawTotal = result['totalChannels'];
    final total = rawTotal is num ? rawTotal.toInt() : channels.length;
    final rawSourceId = (result['sourceId'] as String?)?.trim();
    final rawCategory = (result['selectedCategory'] as String?)?.trim();
    final rawCategories = result['categories'];
    return VpIptvZapPage(
      channels: channels,
      offset: offset,
      // A total that doesn't cover the page it came with would put the
      // category's end behind the window's own last row.
      total: math.max(total, offset + channels.length),
      sourceId: (rawSourceId == null || rawSourceId.isEmpty)
          ? null
          : rawSourceId,
      category: (rawCategory == null || rawCategory.isEmpty)
          ? null
          : rawCategory,
      categories: rawCategories is List
          ? [
              for (final entry in rawCategories.whereType<String>())
                if (entry.isNotEmpty) entry,
            ]
          : const [],
    );
  }

  /// Replace the ring with [page]. The caller tunes afterwards, so the index
  /// left behind here is only a starting point.
  void installIptvZapWindow(
    VpIptvZapPage page, {
    required bool preservePlayingChannel,
  }) {
    if (page.channels.isEmpty) return;
    if (page.category != _host.iptvZapCategory)
      _host.clearIptvZapBoundaryCache();
    final playing = preservePlayingChannel ? _host.currentIptvChannel : null;
    var index = 0;
    if (playing != null) {
      final found = page.channels.indexWhere(
        (candidate) =>
            candidate.url == playing.url && candidate.name == playing.name,
      );
      if (found >= 0) index = found;
    }
    _host.setState(() {
      _host.iptvChannelsOverride = page.channels;
      _host.currentIptvIndex = index;
      _host.iptvZapWindowOffset = page.offset;
      _host.iptvZapCategoryTotal = page.total;
      iptvZapSourceId = page.sourceId ?? iptvZapSourceId;
      _host.iptvZapCategory = page.category;
      if (page.categories.isNotEmpty) _host.iptvZapCategories = page.categories;
      _host.iptvZapPagingActive = true;
    });
  }

  /// Splice a freshly loaded page into the ring, growing the window rather
  /// than replacing it — the channel on screen has to keep its place, and the
  /// guide is looking at the same list.
  void mergeIptvZapPage(VpIptvZapPage page) {
    if (!_host.iptvZapPagingActive || page.channels.isEmpty) return;
    if (page.category != _host.iptvZapCategory) return;
    final channels = _host.effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;

    final windowStart = _host.iptvZapWindowOffset;
    final merged = iptvMergeZapWindow(
      window: channels,
      windowOffset: windowStart,
      page: page.channels,
      pageOffset: page.offset,
    );
    // The page didn't touch the window — see iptvMergeZapWindow.
    if (merged == null) return;

    final playing = _host.currentIptvChannel;
    var index = _host.currentIptvIndex + (windowStart - merged.offset);
    if (playing != null) {
      final found = merged.channels.indexWhere(
        (candidate) =>
            candidate.url == playing.url && candidate.name == playing.name,
      );
      if (found >= 0) index = found;
    }
    _host.setState(() {
      _host.iptvChannelsOverride = merged.channels;
      _host.currentIptvIndex = index.clamp(0, merged.channels.length - 1);
      _host.iptvZapWindowOffset = merged.offset;
      _host.iptvZapCategoryTotal = math.max(
        page.total,
        merged.offset + merged.channels.length,
      );
      if (page.categories.isNotEmpty) _host.iptvZapCategories = page.categories;
    });
  }
}
