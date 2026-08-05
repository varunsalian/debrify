import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/iptv_epg_service.dart';
import 'iptv_style.dart';

/// First Edition's editorial hero: the focused channel's programme set like a
/// front-page headline — kicker line, serif title, meta, hairline progress.
///
/// Display-only. Contains NO focus nodes and adds NO actions (the stage owns
/// Watch/Record/Favorite — duplicating focusables above the grid would change
/// the cockpit's UP/DOWN geometry). The caller gates visibility (height
/// budget) and tells it when the schedule pane covers it ([suspended]).
///
/// Data flow, per the plan: paints instantly from `peekNowNext`; a miss
/// fetches `nowNext(url)` behind a 450 ms focus-settle debounce (the stage's
/// pattern) — that call coalesces with the focused row's own `_RowEpg` fetch
/// via the service's in-flight map and LRU cache, so no extra transport
/// happens in the common case. A 60 s ticker re-peeks (`_RowEpg`'s pattern):
/// a self-invalidated cache (programme boundary) refetches, a fresh hit
/// repaints progress. `contextVersion` (XMLTV context replacement) resyncs.
class IptvEditionHero extends StatefulWidget {
  final ValueListenable<IptvChannel?> channel;
  final IptvStyleTokens tokens;

  /// True while the full-day schedule pane covers the guide column — the
  /// hero stays mounted under the Offstage but must not tick or fetch.
  final bool suspended;

  const IptvEditionHero({
    super.key,
    required this.channel,
    required this.tokens,
    this.suspended = false,
  });

  @override
  State<IptvEditionHero> createState() => _IptvEditionHeroState();
}

/// Trailing "(1080p)" style resolution marker in M3U names — same expression
/// the channel row strips with.
final RegExp _heroResExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

class _IptvEditionHeroState extends State<IptvEditionHero> {
  EpgNowNext? _data;
  String? _forUrl;
  Timer? _debounce;
  Timer? _ticker;

  /// Request generation: bumped on every sync and on stop, so a fetch that
  /// straddles an XMLTV context change (same URL, new guide) can't land its
  /// pre-change answer over the fresh data.
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    widget.channel.addListener(_onChannelChanged);
    IptvEpgService.instance.contextVersion.addListener(_onEpgContextChanged);
    if (!widget.suspended) _start();
  }

  @override
  void didUpdateWidget(IptvEditionHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) {
      oldWidget.channel.removeListener(_onChannelChanged);
      widget.channel.addListener(_onChannelChanged);
      // The new listenable's CURRENT value never fires a change — sync to it
      // or the hero keeps painting the old subject.
      if (!widget.suspended) _sync();
    }
    if (oldWidget.suspended != widget.suspended) {
      widget.suspended ? _stop() : _start();
    }
  }

  @override
  void dispose() {
    widget.channel.removeListener(_onChannelChanged);
    IptvEpgService.instance.contextVersion.removeListener(_onEpgContextChanged);
    _stop();
    super.dispose();
  }

  void _start() {
    _sync();
    _ticker ??= Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || widget.suspended) return;
      // Nothing to reconcile for a channel that can't have a guide.
      final ch = widget.channel.value;
      if (ch == null || !IptvEpgService.isEpgCapable(ch)) return;
      final url = _forUrl;
      if (url == null) return;
      final cached = IptvEpgService.instance.peekNowNext(url);
      if (cached == null) {
        _sync(); // cache self-invalidated at a boundary — re-ask
      } else if (!identical(cached, _data)) {
        setState(() => _data = cached);
      } else if (cached.now != null) {
        setState(() {}); // advance the progress rule
      }
    });
  }

  void _stop() {
    _ticket++;
    _debounce?.cancel();
    _debounce = null;
    _ticker?.cancel();
    _ticker = null;
  }

  void _onChannelChanged() {
    if (!mounted || widget.suspended) return;
    // Repaint the identity (kicker/title from channel.value) even when the
    // EPG answer happens to be identical or null-before-and-after — the
    // SUBJECT changed regardless of the data.
    setState(() {});
    _sync();
  }

  void _onEpgContextChanged() {
    if (mounted && !widget.suspended) _sync();
  }

  void _sync() {
    _debounce?.cancel();
    final ticket = ++_ticket;
    final ch = widget.channel.value;
    _forUrl = ch?.url;
    if (ch == null || !IptvEpgService.isEpgCapable(ch)) {
      if (_data != null) setState(() => _data = null);
      return;
    }
    final cached = IptvEpgService.instance.peekNowNext(ch.url);
    if (cached != null) {
      if (!identical(cached, _data)) setState(() => _data = cached);
      return;
    }
    if (_data != null) setState(() => _data = null);
    // Focus-settle debounce: rapid DPAD travel re-arms, only the channel the
    // user stops on pays for a fetch (which the row has usually already
    // started — the service coalesces the two).
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final url = _forUrl;
      if (url == null || !mounted) return;
      try {
        final result = await IptvEpgService.instance.nowNext(url);
        // Stale ticket covers channel changes AND XMLTV context changes on
        // the same URL; suspended covers the schedule pane opening mid-await.
        if (!mounted || ticket != _ticket || widget.suspended) return;
        if (!result.isEmpty) setState(() => _data = result);
      } catch (_) {
        // A failed guide lookup just leaves the hero on the channel name.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final ch = widget.channel.value;
    if (ch == null) return const SizedBox.shrink();

    final resMatch = _heroResExp.firstMatch(ch.name);
    final resolution = resMatch?.group(1)?.toUpperCase();
    final displayName = resMatch == null
        ? ch.name
        : ch.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

    final now = _data?.now;
    final at = DateTime.now();
    final title = now?.title ?? displayName;
    final serif = t.headlineFamily.isEmpty ? null : t.headlineFamily;

    String? meta;
    double? progress;
    if (now != null) {
      final start = TimeOfDay.fromDateTime(now.start).format(context);
      final stop = TimeOfDay.fromDateTime(now.stop).format(context);
      final left = now.stop.difference(at).inMinutes;
      meta = left > 0
          ? '$start – $stop   ·   $left min left'
          : '$start – $stop';
      progress = now.progressAt(at);
    }

    final kicker = [
      if (ch.channelNumber != null) 'CH ${ch.channelNumber}',
      displayName.toUpperCase(),
      if (resolution != null) resolution,
    ].join('   ·   ');

    return Container(
      height: 128,
      padding: const EdgeInsets.fromLTRB(14, 16, 24, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (ch.isLive) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: t.live,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: t.live.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ON AIR',
                  style: TextStyle(
                    color: t.live,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  kicker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.fgDim,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.fg,
              fontSize: 34,
              height: 1.05,
              letterSpacing: -0.4,
              fontFamily: serif,
            ),
          ),
          const SizedBox(height: 6),
          if (meta != null)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.fgDim,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 420,
              height: 2,
              child: Row(
                children: [
                  Expanded(
                    flex: (progress * 1000).round().clamp(0, 1000),
                    child: ColoredBox(color: t.fg),
                  ),
                  Expanded(
                    flex: 1000 - (progress * 1000).round().clamp(0, 1000),
                    child: ColoredBox(color: t.hairline),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
