import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:flutter/material.dart';

class _LogoOrTitle extends StatelessWidget {
  final String? url;
  final String name;

  /// Compact identity centers its whole stack; the logo art follows.
  final bool centered;

  const _LogoOrTitle({
    required this.url,
    required this.name,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final alignment = centered ? Alignment.bottomCenter : Alignment.bottomLeft;
    // Metahub ships some logos as BLACK wordmarks, invisible on ink — roughly
    // one title in four. The text fallback is not a degraded path, it is the
    // other half of the design.
    final text = Text(
      name,
      maxLines: 2,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: centered ? 32 : 39 * m.k,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: sInk,
      ),
    );
    // Keep one stable title-art viewport from the first frame. A loose
    // ConstrainedBox let CachedNetworkImage adopt its placeholder's intrinsic
    // width and then relayout around the decoded logo, which made the wordmark
    // visibly slide into place on slower TVs.
    return SizedBox(
      width: 235 * m.k,
      height: 60 * m.k,
      child: Align(
        alignment: alignment,
        child: (url == null || url!.isEmpty)
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: alignment,
                child: text,
              )
            : CachedNetworkImage(
                imageUrl: url!,
                width: 235 * m.k,
                height: 60 * m.k,
                fit: BoxFit.contain,
                alignment: alignment,
                cacheManager: DebrifyImageCache.manager,
                memCacheWidth: 520,
                placeholder: (_, __) => const SizedBox.expand(),
                errorWidget: (_, __, ___) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: alignment,
                  child: text,
                ),
              ),
      ),
    );
  }
}

typedef SLogoOrTitle = _LogoOrTitle;
const showcaseLogoOrTitleConstructor = _LogoOrTitle.new;

/// Two lines + MORE; tapping expands in place (the identity band grows).
/// Collapse comes back with LESS — a one-way expander leaves a wall of text
/// parked over the artwork.
class _ExpandableSynopsis extends StatefulWidget {
  final String text;
  const _ExpandableSynopsis({required this.text});

  @override
  State<_ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

typedef SExpandableSynopsis = _ExpandableSynopsis;
const showcaseExpandableSynopsisConstructor = _ExpandableSynopsis.new;

class _ExpandableSynopsisState extends State<_ExpandableSynopsis> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            maxLines: _open ? null : 2,
            textAlign: TextAlign.center,
            overflow: _open ? null : TextOverflow.ellipsis,
            style: st(12.5, a: 0.78).copyWith(height: 1.5),
          ),
          const SizedBox(height: 3),
          Text(
            _open ? 'LESS' : 'MORE',
            style: st(
              10.5,
              w: FontWeight.w700,
              a: 0.9,
            ).copyWith(letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4 * m.k),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 7.5 * m.k,
          vertical: 3.5 * m.k,
        ),
        child: Text(label, style: st(9.5 * m.k, w: FontWeight.w600)),
      ),
    );
  }
}

typedef SChip = _Chip;
const showcaseChipConstructor = _Chip.new;

/// The meta line — and where the trackers live.
///
/// Trakt and Simkl are READOUT here, not buttons: filled when tracked, hollow
/// when not, never focusable. Tracker state describes what a title is to you;
/// it is not an errand you came to the page to run, and a row of verbs is the
/// wrong place for it. The branded tracker buttons open their matching sheet.
class _MetaLine extends StatelessWidget {
  final DetailModel model;

  const _MetaLine({required this.model});

  @override
  Widget build(BuildContext context) {
    final m = model;
    final scale = ShowcaseMetrics.of(context).k;
    final bits = <String>[
      if (m.isMovie) 'Film' else 'Series',
      ...m.genres.take(2),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(bits.join(' · '), style: st(10.5 * scale, a: 0.86)),
        if (m.rating != null) ...[
          const SizedBox(width: 7),
          _RatingBox(value: m.rating!),
        ],
        if (m.hasTrakt) ...[
          const SizedBox(width: 8),
          _TrackerMark(
            letter: 'T',
            on: m.traktTracked,
            tint: const Color(0xFFED1C24),
          ),
        ],
        if (m.hasSimkl) ...[
          const SizedBox(width: 5),
          _TrackerMark(
            letter: 'S',
            on: m.simklTracked,
            tint: const Color(0xFF0B87C4),
          ),
        ],
        if (m.hasMdblist) ...[
          const SizedBox(width: 5),
          _TrackerMark(letter: 'M', on: m.mdblistTracked, tint: kMdblistPurple),
        ],
      ],
    );
  }
}

typedef SMetaLine = _MetaLine;
const showcaseMetaLineConstructor = _MetaLine.new;

class _TrackerMark extends StatelessWidget {
  final String letter;
  final bool on;
  final Color tint;

  const _TrackerMark({
    required this.letter,
    required this.on,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Container(
      width: 15 * k,
      height: 15 * k,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? tint : null,
        border: on
            ? null
            : Border.all(color: sInk.withValues(alpha: 0.34), width: 0.75),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 7 * k,
          fontWeight: FontWeight.w800,
          color: on ? sInk : sInk.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _RatingBox extends StatelessWidget {
  final double value;

  const _RatingBox({required this.value});

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 3 * k, vertical: 0.5 * k),
      decoration: BoxDecoration(
        border: Border.all(color: sInk.withValues(alpha: 0.45), width: 0.75),
        borderRadius: BorderRadius.circular(2.5 * k),
      ),
      child: Text('★ ${value.toStringAsFixed(1)}', style: st(7.5 * k, a: 0.9)),
    );
  }
}

/// The honors row — IMDb Top 250 position and the popularity meter, as
/// hairline small-caps chips in the family of [_RatingBox]. Readout, never
/// focusable; monochrome so it sits under the artwork instead of on top of it.
class _HonorsLine extends StatelessWidget {
  final DetailModel model;

  const _HonorsLine({required this.model});

  @override
  Widget build(BuildContext context) {
    final x = model.imdbExtra;
    if (x == null) return const SizedBox.shrink();
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    final chips = <Widget>[
      if (x.top250Rank != null)
        _honorChip(m, 'IMDb TOP 250', '№${x.top250Rank}'),
      if (x.meterRank != null)
        _honorChip(
          m,
          'TRENDING',
          '№${x.meterRank}',
          drift: switch (x.meterDelta) {
            null || 0 => null,
            final d when d > 0 => '▴$d',
            final d => '▾${-d}',
          },
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: compact ? WrapAlignment.center : WrapAlignment.start,
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  Widget _honorChip(
    ShowcaseMetrics m,
    String label,
    String rank, {
    String? drift,
  }) {
    final compact = m.compact;
    final size = compact ? 9.5 : 7.5 * m.k;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 6 * m.k,
        vertical: compact ? 3.5 : 2.5 * m.k,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: sInk.withValues(alpha: 0.30), width: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: st(
              size,
              w: FontWeight.w700,
              a: 0.62,
            ).copyWith(letterSpacing: 0.8),
          ),
          Text(
            rank,
            style: st(
              size,
              w: FontWeight.w700,
              a: 0.95,
            ).copyWith(letterSpacing: 0.4),
          ),
          if (drift != null)
            Text(' $drift', style: st(size, w: FontWeight.w700, a: 0.45)),
        ],
      ),
    );
  }
}

typedef SHonorsLine = _HonorsLine;
const showcaseHonorsLineConstructor = _HonorsLine.new;

/// Year · seasons/runtime. NOT Dolby/CC/HDR badges: nothing is fetched at page
/// open, so those could only ever be decoration pretending to be data.
class _TechLine extends StatelessWidget {
  final DetailModel model;

  const _TechLine({required this.model});

  @override
  Widget build(BuildContext context) {
    final bits = <String>[
      if ((model.year ?? '').isNotEmpty) model.year!,
      if ((model.runtime ?? '').isNotEmpty) model.runtime!,
      if ((model.certificate ?? '').isNotEmpty) model.certificate!,
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    return Text(
      bits.join('  ·  '),
      style: st(9.5 * ShowcaseMetrics.of(context).k, a: 0.7),
    );
  }
}

typedef STechLine = _TechLine;
const showcaseTechLineConstructor = _TechLine.new;
