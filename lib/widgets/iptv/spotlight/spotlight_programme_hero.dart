import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/debrify_image_cache.dart';
import '../../../services/iptv_epg_service.dart';
import '../styles/iptv_style.dart';
import 'spotlight_hero_chrome.dart';

typedef SpotlightHeroActionsBuilder =
    Widget Function(BuildContext context, EpgProgramme? programme, bool dense);

/// Binds the selected channel's existing now/next data to the approved
/// Spotlight hero chrome. Playback remains a caller-owned slot so the native
/// preview subtree is inserted once and unchanged.
class SpotlightProgrammeHero extends StatefulWidget {
  final IptvChannel? channel;
  final EpgProgramme? selectedProgramme;
  final Widget previewSlot;
  final SpotlightHeroActionsBuilder actionsBuilder;

  const SpotlightProgrammeHero({
    super.key,
    required this.channel,
    this.selectedProgramme,
    required this.previewSlot,
    required this.actionsBuilder,
  });

  @override
  State<SpotlightProgrammeHero> createState() => _SpotlightProgrammeHeroState();
}

class _SpotlightProgrammeHeroState extends State<SpotlightProgrammeHero> {
  EpgNowNext? _guide;
  Timer? _settle;
  Timer? _ticker;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    IptvEpgService.instance.contextVersion.addListener(_onContextChanged);
    _sync();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (widget.selectedProgramme != null) {
        // Programme-dependent Watch/Replay/Record/Guide actions must cross
        // their time boundary even when the guide object itself is unchanged.
        setState(() {});
        return;
      }
      final channel = widget.channel;
      if (channel == null || !IptvEpgService.isEpgCapable(channel)) return;
      final cached = IptvEpgService.instance.peekNowNext(channel.url);
      if (cached == null) {
        _sync();
      } else {
        setState(() => _guide = cached);
      }
    });
  }

  @override
  void didUpdateWidget(SpotlightProgrammeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.channel, widget.channel)) _sync();
  }

  @override
  void dispose() {
    _ticket++;
    _settle?.cancel();
    _ticker?.cancel();
    IptvEpgService.instance.contextVersion.removeListener(_onContextChanged);
    super.dispose();
  }

  void _onContextChanged() {
    if (mounted) _sync();
  }

  void _sync() {
    _settle?.cancel();
    final ticket = ++_ticket;
    final channel = widget.channel;
    if (channel == null || !IptvEpgService.isEpgCapable(channel)) {
      if (_guide != null) setState(() => _guide = null);
      return;
    }
    final cached = IptvEpgService.instance.peekNowNext(channel.url);
    if (cached != null) {
      setState(() => _guide = cached);
      return;
    }
    if (_guide != null) setState(() => _guide = null);
    _settle = Timer(const Duration(milliseconds: 375), () async {
      try {
        final guide = await IptvEpgService.instance.nowNext(channel.url);
        if (!mounted ||
            ticket != _ticket ||
            !identical(channel, widget.channel)) {
          return;
        }
        setState(() => _guide = guide);
      } catch (_) {
        // Programme data is optional; the channel identity remains useful.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final programme = widget.selectedProgramme ?? _guide?.now;
    final title = programme?.title ?? channel?.name ?? 'Choose a channel';
    final identity = channel == null
        ? 'LIVE TV'
        : <String>[
            if (channel.channelNumber != null) '${channel.channelNumber}',
            channel.name.toUpperCase(),
          ].join('  ·  ');

    return LayoutBuilder(
      builder: (context, constraints) => SpotlightHeroChrome(
        identitySlot: Row(
          children: [
            _HeroMark(channel: channel),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                identity,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: IptvStyleTokens.spotlight.fgDim,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
        titleSlot: Text(title),
        metadataSlot: programme == null
            ? Text(channel?.group ?? 'Select a row to preview')
            : _ProgrammeMeta(programme: programme),
        descriptionSlot:
            programme == null || programme.description.trim().isEmpty
            ? null
            : Text(programme.description.trim()),
        actionsSlot: widget.actionsBuilder(
          context,
          programme,
          constraints.maxHeight < kSpotlightHeroDenseBreakpoint,
        ),
        previewSlot: widget.previewSlot,
      ),
    );
  }
}

class _ProgrammeMeta extends StatelessWidget {
  final EpgProgramme programme;

  const _ProgrammeMeta({required this.programme});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = TimeOfDay.fromDateTime(programme.start).format(context);
    final stop = TimeOfDay.fromDateTime(programme.stop).format(context);
    final t = IptvStyleTokens.spotlight;
    if (programme.start.isAfter(now)) {
      final until = programme.start.difference(now).inMinutes;
      return Text(
        '$start–$stop  ·  Starts ${until < 1 ? 'soon' : 'in $until min'}',
      );
    }
    if (!programme.stop.isAfter(now)) {
      return Text('$start–$stop  ·  Ended');
    }
    final left = programme.stop.difference(now).inMinutes;
    final progress = programme.progressAt(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$start–$stop${left > 0 ? '  ·  $left min left' : ''}'),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: t.hairline2,
            valueColor: AlwaysStoppedAnimation<Color>(t.accent),
          ),
        ),
      ],
    );
  }
}

class _HeroMark extends StatelessWidget {
  final IptvChannel? channel;

  const _HeroMark({required this.channel});

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final fallback = Icon(Icons.live_tv_rounded, color: t.fgMid, size: 18);
    final logo = channel?.logoUrl?.trim();
    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.hairline),
      ),
      child: logo == null || logo.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: logo,
              cacheManager: DebrifyImageCache.iptvLogos,
              fit: BoxFit.contain,
              memCacheHeight: 96,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}
