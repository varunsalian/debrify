import 'package:flutter/material.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../models/debrify_tv/channel_stats.dart';
import '../../../models/debrify_tv_cache.dart';
import '../../../theme/app_theme.dart' show DebrifyTvTokens;
import '../../../theme/app_theme_scope.dart';
import '../../../utils/formatters.dart';
import 'debrify_tv_view.dart' show kThinPoolThreshold;
import 'spotlight_rail.dart' show SpotlightKick;

/// The acting stage beside the rail: the focused channel's identity, its
/// numbers, a sample of its pool, and the action row. Purely presentational —
/// focus routing lives in the arm, data comes from the view.
///
/// The stage may NOT promise what plays (mock §3): Debrify TV has no running
/// order — `_selectTorrentsForPlayback` ends in a shuffle, provider cache-hit
/// is unknown until the provider answers, and size is a per-file rule. So the
/// strip is captioned a sample of the pool, never "up next", and the only
/// quality number shown is the one filter genuinely applied to the cache
/// pre-shuffle.
class SpotlightStage extends StatelessWidget {
  final DebrifyTvChannel? channel;
  final bool pinned;
  final DebrifyTvChannelStats? stats;
  final bool busy;

  final FocusNode playNode;
  final FocusNode pinNode;
  final FocusNode editNode;
  final FocusNode shareNode;
  final FocusNode deleteNode;
  final FocusNode Function(int) plateNodeFor;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final KeyEventResult Function(int, FocusNode, KeyEvent) onPlateKey;
  final void Function(int) onPlate;

  final VoidCallback onWatch;
  final VoidCallback onTogglePin;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onAdd;
  final VoidCallback onImport;

  const SpotlightStage({
    super.key,
    required this.channel,
    required this.pinned,
    required this.stats,
    required this.busy,
    required this.playNode,
    required this.pinNode,
    required this.editNode,
    required this.shareNode,
    required this.deleteNode,
    required this.plateNodeFor,
    required this.onKey,
    required this.onPlateKey,
    required this.onPlate,
    required this.onWatch,
    required this.onTogglePin,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onAdd,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final ch = channel;
    if (ch == null) {
      // No channels at all. The redesigned empty surface is a phase-7
      // deliverable; until it lands this stays a quiet prompt (the rail's
      // Add / Import rows are the actionable path).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Make a channel out of anything you can name.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: app.core.tx,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add a channel or import a pack from the rail on the left.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: tv.textDim),
            ),
          ],
        ),
      );
    }

    final s = stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Identity + status ───────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SpotlightKick(
                    'Channel ${ch.channelNumber.toString().padLeft(2, '0')}'
                    '${pinned ? ' · Pinned' : ''}',
                    color: tv.accent,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 37,
                      height: 0.98,
                      letterSpacing: -1.2,
                      fontWeight: FontWeight.w800,
                      color: app.core.tx,
                    ),
                  ),
                ],
              ),
            ),
            if (s != null) ...[
              const SizedBox(width: 15),
              _StatusChip(stats: s),
            ],
          ],
        ),
        const SizedBox(height: 13),
        // ── Keywords ────────────────────────────────────────────────
        _KeywordRow(keywords: ch.keywords, yield_: s?.keywordYield),
        const SizedBox(height: 17),
        // ── The numbers the grid never drew ─────────────────────────
        _StatsBand(stats: s),
        const SizedBox(height: 14),
        // ── A sample of the pool ────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: SpotlightKick(
                "What's in this channel",
                color: tv.textFaint,
                fontSize: 9,
              ),
            ),
            Text(
              'a sample of the pool · nothing here is a running order',
              style: TextStyle(fontSize: 10, color: tv.textFaint),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: s == null || s.sample.isEmpty
              ? _EmptyStrip(
                  message: s == null
                      ? 'Reading the pool…'
                      : 'Nothing was pooled for this channel.\n'
                            'None of its keywords returned results — edit '
                            'them and save to build the pool again.',
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < s.sample.length && i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 11),
                      Expanded(
                        child: _SamplePlate(
                          torrent: s.sample[i],
                          focusNode: plateNodeFor(i),
                          onKey: (n, e) => onPlateKey(i, n, e),
                          onActivate: () => onPlate(i),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),
        // ── Actions ─────────────────────────────────────────────────
        Row(
          children: [
            _ActionButton(
              focusNode: playNode,
              onKey: onKey,
              onActivate: busy ? null : onWatch,
              icon: Icons.play_arrow_rounded,
              label: 'Tune in',
              primary: true,
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: pinNode,
              onKey: onKey,
              onActivate: onTogglePin,
              icon: pinned ? Icons.star_rounded : Icons.star_outline_rounded,
              tooltip: pinned ? 'Unpin' : 'Pin to the top of the rail',
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: editNode,
              onKey: onKey,
              onActivate: onEdit,
              icon: Icons.edit_rounded,
              tooltip: 'Edit channel',
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: shareNode,
              onKey: onKey,
              onActivate: onShare,
              icon: Icons.share_rounded,
              tooltip: 'Share channel',
            ),
            const SizedBox(width: 7),
            _ActionButton(
              focusNode: deleteNode,
              onKey: onKey,
              onActivate: onDelete,
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete channel',
              danger: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// Ready / Thin pool / Cache failed, resolved from the focused channel's
/// stats — by the time this draws, the expensive pass has already run.
class _StatusChip extends StatelessWidget {
  final DebrifyTvChannelStats stats;
  const _StatusChip({required this.stats});

  static const _ok = Color(0xFF39D98A);
  static const _warn = Color(0xFFF4B860);
  static const _bad = Color(0xFFFF6673);

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final (Color dot, String head, String detail) = switch (stats) {
      DebrifyTvChannelStats(status: DebrifyTvCacheStatus.failed) => (
        _bad,
        'Cache failed',
        'nothing to play',
      ),
      DebrifyTvChannelStats(pooled: 0) => (
        _bad,
        'Nothing pooled',
        'rebuild this channel',
      ),
      DebrifyTvChannelStats(:final pooled, :final deadKeywords)
          when pooled < kThinPoolThreshold || deadKeywords.isNotEmpty =>
        (_warn, 'Thin pool', 'only ${stats.atYourQuality} at your quality'),
      _ => (_ok, 'Ready', '${stats.pooled} in the pool'),
    };
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tv.fillWeak,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tv.hairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5.5,
            height: 5.5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 5.5),
          Text(
            head,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: app.core.tx,
            ),
          ),
          const SizedBox(width: 5),
          Text(detail, style: TextStyle(fontSize: 10, color: tv.textDim)),
        ],
      ),
    );
  }
}

class _KeywordRow extends StatelessWidget {
  final List<String> keywords;
  final Map<String, int>? yield_;
  const _KeywordRow({required this.keywords, required this.yield_});

  static const int _shown = 5;
  static const _warn = Color(0xFFF4B860);

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final visible = keywords.take(_shown).toList();
    final more = keywords.length - visible.length;
    return SizedBox(
      height: 25,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final kw in visible) _chip(context, tv, kw),
          if (more > 0)
            Container(
              height: 25,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Text(
                '+$more more',
                style: TextStyle(fontSize: 10.5, color: tv.textFaint),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, DebrifyTvTokens tv, String kw) {
    final count = yield_?[kw.toLowerCase()];
    final dead = count == 0;
    return Container(
      height: 25,
      margin: const EdgeInsets.only(right: 5.5),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: dead ? _warn.withValues(alpha: 0.08) : tv.fillWeak,
        borderRadius: BorderRadius.circular(12.5),
        border: Border.all(
          color: dead ? _warn.withValues(alpha: 0.3) : tv.hairline,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kw,
            style: TextStyle(fontSize: 10.5, color: dead ? _warn : tv.textDim),
          ),
          if (count != null) ...[
            const SizedBox(width: 5),
            Text(
              dead ? 'nothing found' : '$count',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: dead ? _warn.withValues(alpha: 0.62) : tv.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Four cards: pool depth, at-your-quality (with the tier mix), keyword
/// health, freshness. Null stats draw quiet em-dashes — never zeros, which
/// would read as a real (alarming) answer.
class _StatsBand extends StatelessWidget {
  final DebrifyTvChannelStats? stats;
  const _StatsBand({required this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final deadCount = s?.deadKeywords.length ?? 0;
    final kwTotal = s?.keywordYield.length ?? 0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              label: 'In the pool',
              value: s == null ? '—' : _thousands(s.pooled),
              caption: 'titles cached for this channel',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'At your quality',
              value: s == null ? '—' : _thousands(s.atYourQuality),
              caption: 'by release name',
              hot: true,
              mix: s?.qualityMix,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'Keywords',
              value: s == null ? '—' : '${kwTotal - deadCount} of $kwTotal',
              caption: s == null
                  ? ''
                  : deadCount > 0
                  ? '“${s.deadKeywords.first}” found nothing'
                  : 'every keyword returned results',
              cold: deadCount > 0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'Freshness',
              value: s == null
                  ? '—'
                  : s.status == DebrifyTvCacheStatus.failed
                  ? 'failed'
                  : _relative(s.fetchedAt),
              caption: s?.status == DebrifyTvCacheStatus.failed
                  ? 'no pool was written'
                  : 'background prefetch keeps it warm',
              smallValue: true,
            ),
          ),
        ],
      ),
    );
  }

  static String _thousands(int n) {
    final t = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (i > 0 && (t.length - i) % 3 == 0) b.write(',');
      b.write(t[i]);
    }
    return b.toString();
  }

  static String _relative(DateTime? at) {
    if (at == null) return 'never';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inHours < 24) {
      return d.inHours == 1 ? 'an hour ago' : '${d.inHours} hours ago';
    }
    if (d.inDays < 7) {
      return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
    }
    if (d.inDays < 14) return 'a week ago';
    return '${(d.inDays / 7).floor()} weeks ago';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final bool hot;
  final bool cold;
  final bool smallValue;
  final List<int>? mix;

  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    this.hot = false,
    this.cold = false,
    this.smallValue = false,
    this.mix,
  });

  static const _warn = Color(0xFFF4B860);

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final m = mix;
    final mixTotal = m == null ? 0 : m.fold<int>(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: hot ? tv.accent.withValues(alpha: 0.10) : tv.fillWeak,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: hot
              ? tv.accent.withValues(alpha: 0.24)
              : cold
              ? _warn.withValues(alpha: 0.26)
              : tv.hairline,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SpotlightKick(
            label,
            color: hot
                ? tv.accent
                : cold
                ? _warn
                : tv.textFaint,
            fontSize: 8.5,
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: smallValue ? 15 : 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: app.core.tx,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, color: cold ? _warn : tv.textFaint),
          ),
          if (m != null && mixTotal > 0) ...[
            const SizedBox(height: 7),
            SizedBox(
              height: 5,
              child: Row(
                children: [
                  for (var i = 0; i < m.length; i++)
                    if (m[i] > 0)
                      Expanded(
                        flex: m[i],
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: i == 0
                                ? tv.accent.withValues(alpha: 0.85)
                                : i == 1
                                ? app.core.tx.withValues(alpha: 0.6)
                                : app.core.tx.withValues(alpha: 0.22),
                          ),
                        ),
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

class _EmptyStrip extends StatelessWidget {
  final String message;
  const _EmptyStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    final tv = AppThemeScope.of(context).debrifyTv;
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tv.hairline, width: 1),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11.5, height: 1.5, color: tv.textDim),
      ),
    );
  }
}

/// One sample plate: the typographic bed (quality badge, matched keyword,
/// raw release name — the zero-network, art-off shippable state) over a meta
/// line. Art plates LIFT on focus; they never invert and never take a ring.
class _SamplePlate extends StatelessWidget {
  final CachedTorrent torrent;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback onActivate;

  const _SamplePlate({
    required this.torrent,
    required this.focusNode,
    required this.onKey,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final String name = torrent.name;
    final int sizeBytes = torrent.sizeBytes;
    final List<String> keywords = torrent.keywords;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return RepaintBoundary(
            child: GestureDetector(
              onTap: onActivate,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                transform: focused
                    ? (Matrix4.identity()
                        ..translateByDouble(0, -5, 0, 1)
                        ..scaleByDouble(1.045, 1.045, 1, 1))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: tv.cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: focused ? app.core.tx : tv.hairline,
                    width: 1,
                  ),
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Color(0x8C000000),
                            blurRadius: 28,
                            offset: Offset(0, 15),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The typographic bed.
                    Container(
                      height: 64,
                      width: double.infinity,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            app.core.tx.withValues(alpha: 0.07),
                            app.core.tx.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _badge(context, _tierLabel(name), strong: true),
                              const Spacer(),
                              if (keywords.isNotEmpty)
                                Flexible(
                                  child: _badge(context, keywords.first),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 7.5,
                              height: 1.35,
                              color: tv.textFaint,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: app.core.tx,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            Formatters.formatFileSize(sizeBytes),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: tv.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _badge(BuildContext context, String text, {bool strong = false}) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 3),
      decoration: BoxDecoration(
        color: app.core.ground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(3.5),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: strong ? app.core.tx : app.core.tx.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  static String _tierLabel(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('2160p')) return '4K';
    if (lower.contains('1080p') || lower.contains('1080i')) return '1080p';
    if (lower.contains('720p') || lower.contains('720i')) return '720p';
    return 'SD';
  }
}

class _ActionButton extends StatelessWidget {
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback? onActivate;
  final IconData icon;
  final String? label;
  final String? tooltip;
  final bool primary;
  final bool danger;

  const _ActionButton({
    required this.focusNode,
    required this.onKey,
    required this.onActivate,
    required this.icon,
    this.label,
    this.tooltip,
    this.primary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKey,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final disabled = onActivate == null;
          // Danger focus is the mock's literal pair — this surface already
          // paints its delete affordances a literal red (grid options menu).
          const dangerFill = Color(0xFFFFE3E5);
          const dangerInk = Color(0xFF8A1420);
          final Color fill = focused
              ? (danger ? dangerFill : app.core.tx)
              : primary
              ? app.core.tx.withValues(alpha: disabled ? 0.4 : 0.92)
              : tv.fillWeak;
          final Color ink = focused
              ? (danger ? dangerInk : app.inkOn(app.core.tx))
              : primary
              ? app.inkOn(app.core.tx)
              : tv.textDim;
          final child = RepaintBoundary(
            child: GestureDetector(
              onTap: onActivate,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: 44,
                width: label == null ? 44 : null,
                padding: label == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 21),
                transform: focused
                    ? (Matrix4.identity()..translateByDouble(0, -3, 0, 1))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: focused ? fill : tv.hairline,
                    width: 1,
                  ),
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Color(0x73000000),
                            blurRadius: 24,
                            offset: Offset(0, 12),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 15, color: ink),
                    if (label != null) ...[
                      const SizedBox(width: 7),
                      Text(
                        label!,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
          if (tooltip == null) return child;
          return Tooltip(message: tooltip!, child: child);
        },
      ),
    );
  }
}
