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
/// Tapping a row opens the channel SHEET: the stage, folded. Its trailing play
/// control keeps playback one tap away. The sheet is a modal route, so it
/// cannot rebuild off the parent's setState; the arm mirrors its latest view
/// into a [ValueNotifier] and the sheet listens to that, which is how the stats
/// land after their debounced pass finishes.
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
  final TextEditingController _search = TextEditingController();

  @override
  void didUpdateWidget(SpotlightPhoneArm old) {
    super.didUpdateWidget(old);
    _live.value = widget.view;
  }

  @override
  void dispose() {
    _search.dispose();
    _live.dispose();
    super.dispose();
  }

  List<DebrifyTvChannel> _orderedOf(DebrifyTvView v) => [
    ...v.channels.where((c) => v.favoriteIds.contains(c.id)),
    ...v.channels.where((c) => !v.favoriteIds.contains(c.id)),
  ];

  List<DebrifyTvChannel> _filtered(List<DebrifyTvChannel> channels) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return channels;
    return channels
        .where((channel) {
          final number = channel.channelNumber.toString();
          final paddedNumber = number.padLeft(2, '0');
          return channel.name.toLowerCase().contains(query) ||
              channel.keywords.any(
                (keyword) => keyword.toLowerCase().contains(query),
              ) ||
              number == query ||
              paddedNumber == query;
        })
        .toList(growable: false);
  }

  void _clearSearch() {
    if (_search.text.isEmpty) return;
    _search.clear();
    setState(() {});
  }

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
    final allChannels = _orderedOf(view);
    final ordered = _filtered(allChannels);
    final searching = _search.text.trim().isNotEmpty;
    final pinnedCount = ordered
        .where((c) => view.favoriteIds.contains(c.id))
        .length;

    var pooled = 0;
    for (final c in ordered) {
      pooled += view.railHealth[c.id]?.pooled ?? 0;
    }
    final summary = searching
        ? '${ordered.length} of ${allChannels.length} channels'
        : pooled > 0
        ? '${ordered.length} channels · ${_thousands(pooled)} titles cached'
        : '${ordered.length} ${ordered.length == 1 ? 'channel' : 'channels'}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.sizeOf(context);
        final isLargeSurface = media.shortestSide >= 600;
        final maxWidth = isLargeSurface
            ? (constraints.maxWidth >= 1000 ? 760.0 : 680.0)
            : 560.0;
        final horizontalPadding = constraints.maxWidth < 360
            ? 12.0
            : isLargeSurface
            ? 24.0
            : 20.0;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              key: const ValueKey<String>('debrify-tv-touch-scroll'),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                24 + widget.bottomInset,
              ),
              children: [
                _PhoneHeader(summary: summary, onSettings: view.onSettings),
                const SizedBox(height: 16),
                _PhoneButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Quick Play',
                  primary: true,
                  onTap: view.busy ? null : view.onQuickPlay,
                ),
                const SizedBox(height: 14),
                _PhoneSearchField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  onClear: _clearSearch,
                ),
                // Management actions live at the TOP, beside search — never
                // below a list that can be dozens of channels long.
                const SizedBox(height: 10),
                _PhoneManagementActions(
                  actions: [
                    _PhoneAction(
                      icon: Icons.add_rounded,
                      label: 'Add',
                      onTap: view.busy ? null : view.onAdd,
                    ),
                    _PhoneAction(
                      icon: Icons.cloud_download_rounded,
                      label: 'Import',
                      onTap: view.busy ? null : view.onImport,
                    ),
                    _PhoneAction(
                      icon: Icons.folder_zip_rounded,
                      label: 'Export',
                      onTap: view.busy || allChannels.isEmpty
                          ? null
                          : view.onExport,
                    ),
                    _PhoneAction(
                      icon: Icons.delete_sweep_rounded,
                      label: 'Delete all',
                      onTap: view.busy || allChannels.isEmpty
                          ? null
                          : view.onDeleteAll,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (allChannels.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      'Make a channel out of anything you can name — '
                      'Add or Import above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: app.core.tx,
                      ),
                    ),
                  )
                else if (ordered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 34,
                          color: tv.textFaint,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No channels match “${_search.text.trim()}”',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: app.core.tx,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _clearSearch,
                          child: const Text('Clear search'),
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
              ],
            ),
          ),
        );
      },
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
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openSheet(c),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
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
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
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
                              style: TextStyle(
                                fontSize: 11.5,
                                color: tv.textFaint,
                              ),
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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Play ${c.name}',
                child: Material(
                  color: tv.fillStrong,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: view.busy
                        ? null
                        : () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            view.onWatch(c);
                          },
                    child: SizedBox.square(
                      dimension: 44,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: view.busy ? tv.textFaint : app.core.tx,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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

class _PhoneSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _PhoneSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return TextField(
      key: const ValueKey<String>('debrify-tv-phone-search'),
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: app.core.tx),
      decoration: InputDecoration(
        hintText: 'Search channels',
        hintStyle: TextStyle(color: tv.textFaint),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: tv.textFaint),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
        filled: true,
        fillColor: tv.fillWeak,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: tv.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: tv.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _PhoneAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PhoneAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _PhoneHeader extends StatelessWidget {
  final String summary;
  final VoidCallback onSettings;

  const _PhoneHeader({required this.summary, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;

    Widget title() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            'Channels',
            maxLines: 1,
            style: TextStyle(
              fontSize: 34,
              height: 1,
              letterSpacing: -1,
              fontWeight: FontWeight.w800,
              color: app.core.tx,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: tv.textDim),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(34) > 48;
        final reflowSettings = largeText && constraints.maxWidth < 420;

        if (reflowSettings) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SpotlightKick('Debrify TV', color: tv.accent),
                  ),
                  const SizedBox(width: 12),
                  _PhoneSettingsButton(onTap: onSettings),
                ],
              ),
              const SizedBox(height: 8),
              title(),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpotlightKick('Debrify TV', color: tv.accent),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title()),
                const SizedBox(width: 12),
                _PhoneSettingsButton(onTap: onSettings),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PhoneSettingsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PhoneSettingsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tv = AppThemeScope.of(context).debrifyTv;
    return Material(
      color: tv.fillWeak,
      shape: CircleBorder(side: BorderSide(color: tv.hairline)),
      child: IconButton(
        key: const ValueKey<String>('debrify-tv-phone-settings'),
        tooltip: 'Settings',
        onPressed: onTap,
        icon: const Icon(Icons.settings_rounded),
        iconSize: 21,
        color: tv.textDim,
      ),
    );
  }
}

/// Keeps the primary management actions compact without sacrificing text
/// scaling. Large labels wrap to a balanced 2 + 1 grid instead of taking over
/// the screen as three full-width rows.
class _PhoneManagementActions extends StatelessWidget {
  final List<_PhoneAction> actions;

  const _PhoneManagementActions({required this.actions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final scaledLabel = MediaQuery.textScalerOf(context).scale(13);
        final availableForThree = (constraints.maxWidth - gap * 2) / 3;
        final useTwoColumns = scaledLabel > 17 || availableForThree < 86;

        Widget button(_PhoneAction action) => _PhoneButton(
          icon: action.icon,
          label: action.label,
          compact: true,
          onTap: action.onTap,
        );

        if (!useTwoColumns) {
          return Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: button(actions[i])),
              ],
            ],
          );
        }

        final itemWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(width: itemWidth, child: button(action)),
          ],
        );
      },
    );
  }
}

/// Keeps short actions in one balanced row, then turns them into full-width
/// rows before either a narrow viewport or accessibility text can clip them.
class _PhoneActionGroup extends StatelessWidget {
  final List<_PhoneAction> actions;

  const _PhoneActionGroup({required this.actions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledLabel = MediaQuery.textScalerOf(context).scale(13);
        final availablePerAction =
            (constraints.maxWidth - (actions.length - 1) * 8) / actions.length;
        final stack = scaledLabel > 17 || availablePerAction < 86;

        Widget button(_PhoneAction action) => _PhoneButton(
          icon: action.icon,
          label: action.label,
          compact: true,
          onTap: action.onTap,
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                button(actions[i]),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: button(actions[i])),
            ],
          ],
        );
      },
    );
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
            _PhoneActionGroup(
              actions: [
                _PhoneAction(
                  icon: pinned
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: pinned ? 'Unpin' : 'Pin',
                  onTap: () => view.onToggleFavorite(channel),
                ),
                _PhoneAction(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  onTap: () => popThen(() => view.onEdit(channel)),
                ),
                _PhoneAction(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  onTap: () => popThen(() => view.onShare(channel)),
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
    final cells = [
      _cell(context, 'In the pool', s == null ? '—' : '${s.pooled}', hot: true),
      _cell(context, 'Your quality', s == null ? '—' : '${s.atYourQuality}'),
      _cell(
        context,
        'Keywords',
        s == null ? '—' : '${kwTotal - dead}/$kwTotal',
        cold: dead > 0,
      ),
      _cell(
        context,
        'Fresh',
        s == null
            ? '—'
            : s.status == DebrifyTvCacheStatus.failed
            ? 'failed'
            : _short(s.fetchedAt),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledValue = MediaQuery.textScalerOf(context).scale(14);
        final useGrid = constraints.maxWidth < 330 || scaledValue > 19;
        if (useGrid) {
          final cellWidth = (constraints.maxWidth - 6) / 2;
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final cell in cells) SizedBox(width: cellWidth, child: cell),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: cells[i]),
              ],
            ],
          ),
        );
      },
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
    return Container(
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
    final minHeight = compact ? 40.0 : 48.0;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 16,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: compact ? 16 : 18, color: ink),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
