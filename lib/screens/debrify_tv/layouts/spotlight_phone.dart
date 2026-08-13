import 'package:flutter/material.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../models/debrify_tv/channel_stats.dart';
import '../../../models/debrify_tv_cache.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/formatters.dart';
import 'debrify_tv_view.dart';
import 'spotlight_rail.dart' show SpotlightKick;

/// The Spotlight touch arm: a phone gets a phone — a list, not a TV grid.
///
/// Tapping a row opens the channel SHEET: the stage, folded. The sheet is a
/// modal route, so it cannot rebuild off the parent's setState; the arm
/// mirrors its latest view into a [ValueNotifier] and the sheet listens to
/// that, which is how the stats land after their debounced pass finishes.
///
/// The mock's "Rebuild now" row is deliberately absent: the plan is paint
/// only, and no existing state method rebuilds a pool outside the edit-save
/// flow — Edit remains the rebuild path.
class SpotlightPhoneArm extends StatefulWidget {
  final DebrifyTvView view;
  final double bottomInset;

  const SpotlightPhoneArm({
    super.key,
    required this.view,
    required this.bottomInset,
  });

  @override
  State<SpotlightPhoneArm> createState() => _SpotlightPhoneArmState();
}

class _SpotlightPhoneArmState extends State<SpotlightPhoneArm> {
  late final ValueNotifier<DebrifyTvView> _live = ValueNotifier(widget.view);

  @override
  void didUpdateWidget(SpotlightPhoneArm old) {
    super.didUpdateWidget(old);
    _live.value = widget.view;
  }

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  List<DebrifyTvChannel> _orderedOf(DebrifyTvView v) => [
    ...v.channels.where((c) => v.favoriteIds.contains(c.id)),
    ...v.channels.where((c) => !v.favoriteIds.contains(c.id)),
  ];

  void _openSheet(DebrifyTvChannel channel) {
    // Kick the stats pass before the sheet draws.
    widget.view.onChannelFocused(channel);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ValueListenableBuilder<DebrifyTvView>(
        valueListenable: _live,
        builder: (context, v, _) {
          // The channel object can be replaced by an edit while the sheet is
          // up; follow the id.
          final current = v.channels
              .where((c) => c.id == channel.id)
              .firstOrNull;
          if (current == null) {
            // Deleted underneath us.
            return const SizedBox.shrink();
          }
          return _ChannelSheet(view: v, channel: current);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final view = widget.view;
    final ordered = _orderedOf(view);
    final pinnedCount = ordered
        .where((c) => view.favoriteIds.contains(c.id))
        .length;

    var pooled = 0;
    for (final c in ordered) {
      pooled += view.railHealth[c.id]?.pooled ?? 0;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + widget.bottomInset),
          children: [
            SpotlightKick('Debrify TV', color: tv.accent),
            const SizedBox(height: 8),
            Text(
              'Channels',
              style: TextStyle(
                fontSize: 34,
                height: 1,
                letterSpacing: -1,
                fontWeight: FontWeight.w800,
                color: app.core.tx,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pooled > 0
                  ? '${ordered.length} channels · '
                        '${_thousands(pooled)} titles cached'
                  : '${ordered.length} '
                        '${ordered.length == 1 ? 'channel' : 'channels'}',
              style: TextStyle(fontSize: 13, color: tv.textDim),
            ),
            const SizedBox(height: 16),
            _PhoneButton(
              icon: Icons.play_arrow_rounded,
              label: 'Quick Play',
              primary: true,
              onTap: view.busy ? null : view.onQuickPlay,
            ),
            const SizedBox(height: 14),
            if (ordered.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Text(
                      'Make a channel out of anything you can name.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: app.core.tx,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PhoneButton(
                      icon: Icons.add_rounded,
                      label: 'Add channel',
                      onTap: view.busy ? null : view.onAdd,
                    ),
                    const SizedBox(height: 8),
                    _PhoneButton(
                      icon: Icons.cloud_download_rounded,
                      label: 'Import',
                      onTap: view.busy ? null : view.onImport,
                    ),
                  ],
                ),
              )
            else ...[
              if (pinnedCount > 0) ...[
                _groupLabel(context, 'Pinned', pinnedCount),
                for (final c in ordered.take(pinnedCount))
                  _row(context, view, c, pinned: true),
                const SizedBox(height: 10),
                _groupLabel(
                  context,
                  'Everything else',
                  ordered.length - pinnedCount,
                ),
              ],
              for (final c in ordered.skip(pinnedCount))
                _row(context, view, c, pinned: false),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PhoneButton(
                    icon: Icons.add_rounded,
                    label: 'Add',
                    compact: true,
                    onTap: view.busy ? null : view.onAdd,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PhoneButton(
                    icon: Icons.cloud_download_rounded,
                    label: 'Import',
                    compact: true,
                    onTap: view.busy ? null : view.onImport,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PhoneButton(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    compact: true,
                    onTap: view.onSettings,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupLabel(BuildContext context, String label, int count) {
    final tv = AppThemeScope.of(context).debrifyTv;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2, right: 2),
      child: Row(
        children: [
          Expanded(
            child: SpotlightKick(label, color: tv.textFaint, fontSize: 10),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tv.textFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    DebrifyTvView view,
    DebrifyTvChannel c, {
    required bool pinned,
  }) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final health = view.railHealth[c.id];
    final caption = health == null
        ? '${c.keywords.length} '
              '${c.keywords.length == 1 ? 'keyword' : 'keywords'}'
        : health.status == DebrifyTvCacheStatus.failed
        ? 'Cache failed — rebuild'
        : '${_thousands(health.pooled)} pooled · '
              '${c.keywords.length} keywords';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: tv.cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openSheet(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tv.fillWeak,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        c.channelNumber.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: app.core.tx.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    if (pinned)
                      Positioned(
                        top: -5,
                        right: -5,
                        child: Icon(
                          Icons.star_rounded,
                          size: 13,
                          color: tv.favorite,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: app.core.tx,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: tv.textFaint),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: tv.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// The stage, folded into a bottom sheet.
class _ChannelSheet extends StatelessWidget {
  final DebrifyTvView view;
  final DebrifyTvChannel channel;

  const _ChannelSheet({required this.view, required this.channel});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final pinned = view.favoriteIds.contains(channel.id);
    // Only stats computed FOR this channel: the sheet can open while the
    // view still carries the previously focused channel's numbers, and a
    // sample tapped in that window would play the wrong channel's torrent.
    final DebrifyTvChannelStats? s = view.stats?.channelId == channel.id
        ? view.stats
        : null;
    final media = MediaQuery.of(context);

    void popThen(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      decoration: BoxDecoration(
        color: tv.dialogBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          20 + media.viewInsets.bottom + media.padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tv.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SpotlightKick(
              'Channel ${channel.channelNumber.toString().padLeft(2, '0')}'
              '${pinned ? ' · Pinned' : ''}',
              color: tv.accent,
            ),
            const SizedBox(height: 6),
            Text(
              channel.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 27,
                height: 1.02,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w800,
                color: app.core.tx,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _keywordsLine(channel.keywords),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: tv.textDim),
            ),
            const SizedBox(height: 16),
            _SheetStats(stats: s),
            if (s != null && s.sample.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SpotlightKick(
                      "What's in it",
                      color: tv.textFaint,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'sample',
                    style: TextStyle(fontSize: 11, color: tv.textFaint),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in s.sample)
                      _SheetSample(
                        torrent: t,
                        onTap: view.busy
                            ? null
                            : () => popThen(() => view.onWatchOne(channel, t)),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            _PhoneButton(
              icon: Icons.play_arrow_rounded,
              label: 'Tune in',
              primary: true,
              onTap: view.busy
                  ? null
                  : () => popThen(() => view.onWatch(channel)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PhoneButton(
                    icon: pinned
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    label: pinned ? 'Unpin' : 'Pin',
                    compact: true,
                    onTap: () => view.onToggleFavorite(channel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PhoneButton(
                    icon: Icons.edit_rounded,
                    label: 'Edit',
                    compact: true,
                    onTap: () => popThen(() => view.onEdit(channel)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PhoneButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    compact: true,
                    onTap: () => popThen(() => view.onShare(channel)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DeleteButton(
              pooled: s?.pooled,
              onTap: () => popThen(() => view.onDelete(channel)),
            ),
          ],
        ),
      ),
    );
  }

  static String _keywordsLine(List<String> keywords) {
    const shown = 4;
    final visible = keywords.take(shown).join(' · ');
    final more = keywords.length - shown;
    return more > 0 ? '$visible · +$more' : visible;
  }
}

class _SheetStats extends StatelessWidget {
  final DebrifyTvChannelStats? stats;
  const _SheetStats({required this.stats});

  static const _warn = Color(0xFFF4B860);

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final dead = s?.deadKeywords.length ?? 0;
    final kwTotal = s?.keywordYield.length ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cell(
          context,
          'In the pool',
          s == null ? '—' : '${s.pooled}',
          hot: true,
        ),
        const SizedBox(width: 6),
        _cell(context, 'Your quality', s == null ? '—' : '${s.atYourQuality}'),
        const SizedBox(width: 6),
        _cell(
          context,
          'Keywords',
          s == null ? '—' : '${kwTotal - dead}/$kwTotal',
          cold: dead > 0,
        ),
        const SizedBox(width: 6),
        _cell(
          context,
          'Fresh',
          s == null
              ? '—'
              : s.status == DebrifyTvCacheStatus.failed
              ? 'failed'
              : _short(s.fetchedAt),
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    String label,
    String value, {
    bool hot = false,
    bool cold = false,
  }) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
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
          children: [
            SpotlightKick(
              label,
              color: hot
                  ? tv.accent
                  : cold
                  ? _warn
                  : tv.textFaint,
              fontSize: 7.5,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: app.core.tx,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(DateTime? at) {
    if (at == null) return 'never';
    final d = DateTime.now().difference(at);
    if (d.inHours < 1) return 'now';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }
}

class _SheetSample extends StatelessWidget {
  final CachedTorrent torrent;
  final VoidCallback? onTap;
  const _SheetSample({required this.torrent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: tv.fillWeak,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 190,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  torrent.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: app.core.tx,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.formatFileSize(torrent.sizeBytes),
                  style: TextStyle(fontSize: 10, color: tv.textFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final bool compact;
  final VoidCallback? onTap;

  const _PhoneButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final disabled = onTap == null;
    final Color fill = primary
        ? app.core.tx.withValues(alpha: disabled ? 0.4 : 0.92)
        : tv.fillWeak;
    final Color ink = primary ? app.inkOn(app.core.tx) : tv.textDim;
    final height = compact ? 40.0 : 48.0;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(height / 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: onTap,
        child: Container(
          height: height,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 16 : 18, color: ink),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final int? pooled;
  final VoidCallback onTap;
  const _DeleteButton({required this.pooled, required this.onTap});

  static const _danger = Color(0xFFFF8A94);

  @override
  Widget build(BuildContext context) {
    final tv = AppThemeScope.of(context).debrifyTv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _danger.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: const Text(
                'Delete channel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _danger,
                ),
              ),
            ),
          ),
        ),
        if (pooled != null && pooled! > 0) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Discards $pooled pooled titles',
              style: TextStyle(fontSize: 10.5, color: tv.textFaint),
            ),
          ),
        ],
      ],
    );
  }
}
