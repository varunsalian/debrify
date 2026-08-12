import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/quick_play_rules.dart';
import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_reveal.dart';
import 'widgets/settings_widgets.dart';

class QuickPlaySettingsPage extends StatefulWidget {
  const QuickPlaySettingsPage({super.key});

  @override
  State<QuickPlaySettingsPage> createState() => _QuickPlaySettingsPageState();
}

String _presetTitle(QuickPlayPreset value) => switch (value) {
  QuickPlayPreset.debrifyDefault => 'Debrify default',
  QuickPlayPreset.addonOrder => 'Follow addon order',
  QuickPlayPreset.bestQuality => 'Best quality',
  QuickPlayPreset.fastest => 'Start fastest',
  QuickPlayPreset.custom => 'Custom',
};

String _presetDescription(QuickPlayPreset value) => switch (value) {
  QuickPlayPreset.debrifyDefault =>
    'Balanced and reliable. Exactly how Quick Play works today.',
  QuickPlayPreset.addonOrder =>
    'Use AIOStreams and other addon results in exact returned order.',
  QuickPlayPreset.bestQuality =>
    'Prefer filters and higher resolution, even when it takes longer.',
  QuickPlayPreset.fastest =>
    'Play the first working direct or ready result with less waiting.',
  QuickPlayPreset.custom => 'Your advanced combination.',
};

IconData _presetIcon(QuickPlayPreset value) => switch (value) {
  QuickPlayPreset.debrifyDefault => Icons.auto_awesome_rounded,
  QuickPlayPreset.addonOrder => Icons.format_list_numbered_rounded,
  QuickPlayPreset.bestQuality => Icons.diamond_rounded,
  QuickPlayPreset.fastest => Icons.bolt_rounded,
  QuickPlayPreset.custom => Icons.tune_rounded,
};

String _sourceDescription(QuickPlaySourceMode value) => switch (value) {
  QuickPlaySourceMode.torrentsThenAddons =>
    'Addon fallback only when engines find nothing',
  QuickPlaySourceMode.addonsThenTorrents =>
    'Engine fallback only when addons find nothing',
  QuickPlaySourceMode.together => 'Search engines and addons together',
  QuickPlaySourceMode.torrentsOnly => 'Do not query stream addons',
  QuickPlaySourceMode.addonsOnly => 'Do not query torrent engines',
};

String _sourceDescriptionForRules(
  QuickPlayRules rules, {
  required bool series,
}) => series && rules.preserveLegacyCombinedPackSearch
    ? 'Today\'s route: packs search both; episodes use addon fallback'
    : _sourceDescription(rules.sourceMode);

String _rankingDescription(QuickPlayRanking value) => switch (value) {
  QuickPlayRanking.debrify => 'Curated relevance and seeders',
  QuickPlayRanking.exactOrder =>
    'Keep returned order; strict filters may remove results',
  QuickPlayRanking.quality => 'Resolution inside each filter tier',
  QuickPlayRanking.smallest => 'Known smaller files first',
  QuickPlayRanking.readyFirst => 'Direct links, then cached/ready torrents',
};

({String summary, List<(String, String)> steps}) _routeFor(
  QuickPlayRules rules, {
  required bool series,
}) {
  if (rules.preset == QuickPlayPreset.custom) {
    return (
      summary:
          'Custom: ${_sourceDescriptionForRules(rules, series: series).toLowerCase()}, ${_rankingDescription(rules.ranking).toLowerCase()}.',
      steps: [
        ('Pinned source', 'Always checked first'),
        ('Find sources', _sourceDescriptionForRules(rules, series: series)),
        ('Rank results', _rankingDescription(rules.ranking)),
        (
          'Recover',
          rules.tryNextOnFailure
              ? 'Try up to ${rules.maxAttempts}'
              : 'Stop after one failure',
        ),
      ],
    );
  }
  if (rules.preset == QuickPlayPreset.addonOrder) {
    return (
      summary: series
          ? 'Pinned first, then exact episode results in addon order.'
          : 'Pinned first, then the exact order returned by your addons.',
      steps: const [
        ('Pinned source', 'Use it if it still plays'),
        ('Ask addons', 'Include direct links'),
        ('Keep exact order', 'No Debrify re-ranking'),
        ('Try in sequence', 'Move on only after failure'),
      ],
    );
  }
  if (rules.preset == QuickPlayPreset.bestQuality) {
    return (
      summary: series
          ? 'Prefer a reusable pack with the strongest quality match.'
          : 'Search enabled sources and rank the strongest match first.',
      steps: [
        const ('Pinned source', 'Use it if it still plays'),
        (series ? 'Search packs' : 'Search together', 'Engines and addons'),
        const ('Rank quality', 'Filters remain primary'),
        (series ? 'Exact episode' : 'Play best match', 'Fallback when needed'),
      ],
    );
  }
  if (rules.preset == QuickPlayPreset.fastest) {
    return (
      summary: series
          ? 'Play the first ready episode without waiting for a pack.'
          : 'Prefer a direct link or ready torrent with the shortest path.',
      steps: const [
        ('Pinned source', 'Use it if it still plays'),
        ('Search together', 'Addons and engines'),
        ('Direct or ready', 'Avoid slow preparation'),
        ('Play first', 'Minimal waiting'),
      ],
    );
  }
  return (
    summary: series
        ? 'Pinned first, then the widest filtered pack, then an exact episode.'
        : 'Pinned first, then filtered torrents, with addon fallback.',
    steps: series
        ? const [
            ('Pinned source', 'Reuse the series source'),
            ('Series pack', 'Complete → multi → season'),
            ('Exact episode', 'Fallback if no pack plays'),
            ('Addon fallback', 'Only if engines find nothing'),
          ]
        : const [
            ('Pinned source', 'Use it if it still plays'),
            ('Torrent engines', 'Keep curated relevance'),
            ('Saved filters', 'Strict match, then relax'),
            ('Addon fallback', 'Only if engines find nothing'),
          ],
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final String? title;

  const _Panel({required this.child, this.padding, this.title});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: app.shape.br(16),
        border: Border.all(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    title!,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Divider(height: 1, color: t.line),
                child,
              ],
            ),
    );
  }
}

class _FocusButton extends StatefulWidget {
  final FocusNode node;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FocusButton({
    super.key,
    required this.node,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FocusButton> createState() => _FocusButtonState();
}

class _FocusButtonState extends State<_FocusButton> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return InkWell(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => focused = v),
      onTap: widget.onTap,
      borderRadius: app.shape.br(10),
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: widget.selected ? t.panel2 : Colors.transparent,
          borderRadius: app.shape.br(10),
          border: Border.all(
            color: focused ? t.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PresetCard extends StatefulWidget {
  final FocusNode node;
  final QuickPlayPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetCard({
    super.key,
    required this.node,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return InkWell(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => focused = v),
      onTap: widget.onTap,
      borderRadius: app.shape.br(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.selected ? t.accent.withValues(alpha: .1) : t.panel,
          borderRadius: app.shape.br(16),
          border: Border.all(
            color: focused
                ? t.accent
                : widget.selected
                ? t.accent.withValues(alpha: .5)
                : t.line,
            width: focused ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _presetIcon(widget.preset),
                  color: widget.selected ? t.accent2 : t.dim,
                  size: 21,
                ),
                const Spacer(),
                Icon(
                  widget.selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: widget.selected ? t.accent2 : t.dim2,
                  size: 18,
                ),
              ],
            ),
            const Spacer(),
            Text(
              _presetTitle(widget.preset),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _presetDescription(widget.preset),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.dim, fontSize: 11.5, height: 1.3),
            ),
            if (widget.preset == QuickPlayPreset.debrifyDefault) ...[
              const SizedBox(height: 7),
              const _Badge('CURRENT BEHAVIOR'),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: .14),
        borderRadius: app.shape.br(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: t.accent2,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String subtitle;
  const _Step(this.number, this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: t.line),
              borderRadius: app.shape.br(8),
            ),
            child: Text(
              '$number',
              style: TextStyle(color: t.accent2, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: t.dim, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SelectRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 32, child: Icon(icon, color: t.dim, size: 21)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: t.dim, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 610) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 11), child],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 18),
              SizedBox(width: 320, child: child),
            ],
          );
        },
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  final FocusNode node;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool expanded;

  const _ActionRow({
    required this.node,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.expanded,
  });

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return InkWell(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => focused = v),
      onTap: widget.onTap,
      borderRadius: app.shape.br(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: focused ? t.panel2 : t.panel,
          borderRadius: app.shape.br(14),
          border: Border.all(color: focused ? t.accent : t.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Icon(widget.icon, color: focused ? t.accent2 : t.dim),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle,
                    style: TextStyle(color: t.dim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: widget.expanded ? .25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.chevron_right_rounded, color: t.dim),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickPlaySettingsPageState extends State<QuickPlaySettingsPage> {
  bool _loading = true;
  bool _series = false;
  bool _advanced = false;
  bool _pikPak = false;
  late QuickPlayRules _movie;
  late QuickPlayRules _show;

  final _movieTab = FocusNode(debugLabel: 'quick-play-movies-tab');
  final _seriesTab = FocusNode(debugLabel: 'quick-play-series-tab');
  final _presetNodes = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'quick-play-preset-$i'),
  );
  final _filters = FocusNode(debugLabel: 'quick-play-filters');
  final _packs = FocusNode(debugLabel: 'quick-play-packs');
  final _failure = FocusNode(debugLabel: 'quick-play-failure');
  final _direct = FocusNode(debugLabel: 'quick-play-direct');
  final _advancedNode = FocusNode(debugLabel: 'quick-play-advanced');
  final _source = FocusNode(debugLabel: 'quick-play-source');
  final _ranking = FocusNode(debugLabel: 'quick-play-ranking');
  final _relax = FocusNode(debugLabel: 'quick-play-relax');
  final _validate = FocusNode(debugLabel: 'quick-play-validate');
  final _packOrder = FocusNode(debugLabel: 'quick-play-pack-order');
  final _searchWait = FocusNode(debugLabel: 'quick-play-search-wait');
  final _addonWait = FocusNode(debugLabel: 'quick-play-addon-wait');
  final _packCache = FocusNode(debugLabel: 'quick-play-pack-cache');
  final _reset = FocusNode(debugLabel: 'quick-play-reset');

  static const _presets = [
    QuickPlayPreset.debrifyDefault,
    QuickPlayPreset.addonOrder,
    QuickPlayPreset.bestQuality,
    QuickPlayPreset.fastest,
  ];

  QuickPlayRules get _rules => _series ? _show : _movie;
  bool get _isMovie => !_series;
  FocusNode get _activeTab => _series ? _seriesTab : _movieTab;

  int get _presetColumnCount {
    final horizontalPadding = PlatformUtil.isTelevision ? 72.0 : 32.0;
    final available = MediaQuery.sizeOf(context).width - horizontalPadding;
    final width = available > 980 ? 980.0 : available;
    return width >= 760
        ? 4
        : width >= 480
        ? 2
        : 1;
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('quick_play_settings');
    _load();
  }

  Future<void> _load() async {
    final movie = await StorageService.getQuickPlayRules(isMovie: true);
    final show = await StorageService.getQuickPlayRules(isMovie: false);
    final provider = await StorageService.getDefaultTorrentProvider();
    if (!mounted) return;
    setState(() {
      _movie = movie;
      _show = show;
      _pikPak = provider == 'pikpak';
      _loading = false;
    });
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _movieTab.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final node in [
      _movieTab,
      _seriesTab,
      ..._presetNodes,
      _filters,
      _packs,
      _failure,
      _direct,
      _advancedNode,
      _source,
      _ranking,
      _relax,
      _validate,
      _packOrder,
      _searchWait,
      _addonWait,
      _packCache,
      _reset,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _save(QuickPlayRules rules) async {
    final isMovie = _isMovie;
    setState(() {
      if (isMovie) {
        _movie = rules;
      } else {
        _show = rules;
      }
    });
    await StorageService.setQuickPlayRules(rules, isMovie: isMovie);
  }

  QuickPlayRules _custom(QuickPlayRules candidate) {
    final compatible = candidate.copyWith(
      preset: QuickPlayPreset.debrifyDefault,
    );
    return compatible == QuickPlayRules.debrifyDefault(isMovie: _isMovie)
        ? compatible
        : candidate.copyWith(preset: QuickPlayPreset.custom);
  }

  Future<void> _change(QuickPlayRules Function(QuickPlayRules) change) =>
      _save(_custom(change(_rules)));

  void _focus(FocusNode node) {
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) tvRevealMinimal(ctx);
    });
  }

  List<FocusNode> get _vertical => [
    _filters,
    if (_series) _packs,
    _failure,
    _direct,
    _advancedNode,
    if (_advanced) ...[
      _source,
      _ranking,
      _relax,
      _validate,
      if (_series) _packOrder,
      _searchWait,
      _addonWait,
      if (_series) _packCache,
    ],
    _reset,
  ];

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final current = FocusManager.instance.primaryFocus;
    if ((key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) &&
        _advanced) {
      setState(() => _advanced = false);
      _focus(_advancedNode);
      return KeyEventResult.handled;
    }
    if (current == null) return KeyEventResult.ignored;

    if (current == _movieTab || current == _seriesTab) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _focus(_movieTab);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _focus(_seriesTab);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        final selected = _presets.indexOf(_rules.preset);
        _focus(_presetNodes[selected < 0 ? 0 : selected]);
        return KeyEventResult.handled;
      }
    }

    final preset = _presetNodes.indexOf(current);
    if (preset >= 0) {
      final columns = _presetColumnCount;
      final column = preset % columns;
      if (key == LogicalKeyboardKey.arrowLeft && column > 0) {
        _focus(_presetNodes[preset - 1]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          column < columns - 1 &&
          preset < 3) {
        _focus(_presetNodes[preset + 1]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _focus(preset >= columns ? _presetNodes[preset - columns] : _activeTab);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _focus(
          preset + columns < _presetNodes.length
              ? _presetNodes[preset + columns]
              : _filters,
        );
        return KeyEventResult.handled;
      }
    }

    final vertical = _vertical;
    final i = vertical.indexOf(current);
    if (i >= 0 && key == LogicalKeyboardKey.arrowUp) {
      if (i == 0) {
        final selected = _presets.indexOf(_rules.preset);
        _focus(_presetNodes[selected < 0 ? 0 : selected]);
      } else {
        _focus(vertical[i - 1]);
      }
      return KeyEventResult.handled;
    }
    if (i >= 0 &&
        key == LogicalKeyboardKey.arrowDown &&
        i < vertical.length - 1) {
      _focus(vertical[i + 1]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Quick Play',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Quick Play',
      body: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            PlatformUtil.isTelevision ? 36 : 16,
            18,
            PlatformUtil.isTelevision ? 36 : 16,
            64,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsPageHeader(
                    icon: Icons.bolt_rounded,
                    title: 'Quick Play',
                    subtitle:
                        'Choose what Debrify plays automatically. Movies and series have separate rules.',
                  ),
                  const SizedBox(height: 22),
                  _tabs(),
                  const SizedBox(height: 24),
                  _heading(
                    'How should Debrify choose?',
                    'Pick one behavior, then fine-tune only if needed.',
                  ),
                  const SizedBox(height: 12),
                  _presetGrid(),
                  const SizedBox(height: 18),
                  _routePreview(),
                  const SizedBox(height: 24),
                  _heading(
                    'Useful adjustments',
                    'The choices most people need.',
                  ),
                  const SizedBox(height: 10),
                  _essentials(),
                  if (_pikPak) ...[
                    const SizedBox(height: 12),
                    const SettingsInfoBanner(
                      text:
                          'PikPak safely skips pack probing and tries one torrent because each probe creates an offline download.',
                    ),
                  ],
                  const SizedBox(height: 18),
                  _action(
                    node: _advancedNode,
                    icon: Icons.tune_rounded,
                    title: 'Advanced control',
                    subtitle: 'Source priority, ordering, waiting, and safety',
                    expanded: _advanced,
                    onTap: () => setState(() => _advanced = !_advanced),
                  ),
                  if (_advanced) ...[
                    const SizedBox(height: 10),
                    _advancedControls(),
                  ],
                  const SizedBox(height: 18),
                  _action(
                    node: _reset,
                    icon: Icons.restore_rounded,
                    title: 'Restore today\'s behavior',
                    subtitle: 'Reset Movie and Series rules to Debrify default',
                    onTap: _restore,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String subtitle) {
    final dim = AppThemeScope.of(context).settings.dim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: dim)),
      ],
    );
  }

  Widget _tabs() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 430),
    child: _Panel(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _FocusButton(
              key: const ValueKey('quick-play-tab-movie'),
              node: _movieTab,
              selected: !_series,
              label: 'Movies',
              onTap: () => setState(() => _series = false),
            ),
          ),
          Expanded(
            child: _FocusButton(
              key: const ValueKey('quick-play-tab-series'),
              node: _seriesTab,
              selected: _series,
              label: 'Series',
              onTap: () => setState(() => _series = true),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _presetGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760
          ? 4
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: columns == 1 ? 142 : 184,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (context, i) {
          final preset = _presets[i];
          return _PresetCard(
            key: ValueKey('quick-play-preset-${preset.name}'),
            node: _presetNodes[i],
            preset: preset,
            selected: _rules.preset == preset,
            onTap: () =>
                _save(QuickPlayRules.forPreset(preset, isMovie: _isMovie)),
          );
        },
      );
    },
  );

  Widget _routePreview() {
    final data = _routeFor(_rules, series: _series);
    final t = AppThemeScope.of(context).settings;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What happens for ${_series ? 'a series episode' : 'a movie'}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(data.summary, style: TextStyle(color: t.dim)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Badge(_presetTitle(_rules.preset)),
              ],
            ),
          ),
          Divider(height: 1, color: t.line),
          LayoutBuilder(
            builder: (context, c) {
              final items = [
                for (var i = 0; i < data.steps.length; i++)
                  _Step(i + 1, data.steps[i].$1, data.steps[i].$2),
              ];
              return Padding(
                padding: const EdgeInsets.all(12),
                child: c.maxWidth >= 650
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [for (final w in items) Expanded(child: w)],
                      )
                    : Column(children: items),
              );
            },
          ),
          if (_rules.preset == QuickPlayPreset.debrifyDefault)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SettingsInfoBanner(
                text:
                    'This is today\'s shipped behavior. The steps above are the exact active order.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _essentials() => _Panel(
    child: Column(
      children: [
        SettingsToggleTile(
          focusNode: _filters,
          icon: Icons.filter_alt_rounded,
          title: 'Use my saved filters',
          subtitle:
              _rules.ranking == QuickPlayRanking.exactOrder &&
                  _rules.relaxFilters
              ? 'Exact order wins; filters will not rearrange results'
              : _rules.relaxFilters
              ? 'Prefer matches, then relax filters if needed'
              : 'Only use complete filter matches',
          value: _rules.useFilters,
          onChanged: (v) => _change((r) => r.copyWith(useFilters: v)),
        ),
        if (_series) ...[
          _divider(),
          SettingsToggleTile(
            focusNode: _packs,
            icon: Icons.video_library_rounded,
            title: 'Prefer a reusable pack',
            subtitle: 'Keep later episodes on the same source',
            value: _rules.preferSeriesPacks,
            onChanged: (v) => _change(
              (r) => r.copyWith(
                preferSeriesPacks: v,
                packPreference: v
                    ? QuickPlayPackPreference.widestFirst
                    : QuickPlayPackPreference.exactEpisodeOnly,
              ),
            ),
          ),
        ],
        _divider(),
        _selectRow(
          icon: Icons.replay_rounded,
          title: 'If a result fails',
          subtitle: 'Try another source instead of stopping',
          node: _failure,
          value: _rules.tryNextOnFailure ? '${_rules.maxAttempts}' : '1',
          options: const [
            SettingsSelectOption('1', 'Stop immediately'),
            SettingsSelectOption('3', 'Try up to 3'),
            SettingsSelectOption('5', 'Try up to 5'),
            SettingsSelectOption('10', 'Try up to 10'),
          ],
          onChanged: (v) {
            final n = int.parse(v);
            _change((r) => r.copyWith(tryNextOnFailure: n > 1, maxAttempts: n));
          },
        ),
        _divider(),
        SettingsToggleTile(
          focusNode: _direct,
          icon: Icons.link_rounded,
          title: 'Direct links',
          subtitle: 'Allow playable links returned by addons',
          value: _rules.allowDirectLinks,
          onChanged: (v) => _change((r) => r.copyWith(allowDirectLinks: v)),
        ),
      ],
    ),
  );

  Widget _advancedControls() => Column(
    children: [
      _Panel(
        title: 'Where to look and how to rank',
        child: Column(
          children: [
            _selectRow(
              icon: Icons.account_tree_rounded,
              title: 'Source order',
              subtitle: _sourceDescriptionForRules(_rules, series: _series),
              node: _source,
              value: _series && _rules.preserveLegacyCombinedPackSearch
                  ? 'legacySeriesRoute'
                  : _rules.sourceMode.name,
              options: [
                if (_series)
                  const SettingsSelectOption(
                    'legacySeriesRoute',
                    'Today\'s series route',
                    'Packs search both; exact episodes use addon fallback',
                  ),
                const SettingsSelectOption(
                  'torrentsThenAddons',
                  'Torrent engines, then addons',
                ),
                const SettingsSelectOption(
                  'addonsThenTorrents',
                  'Addons, then torrent engines',
                ),
                const SettingsSelectOption('together', 'Search both together'),
                const SettingsSelectOption(
                  'torrentsOnly',
                  'Torrent engines only',
                ),
                const SettingsSelectOption('addonsOnly', 'Addons only'),
              ],
              onChanged: (v) => _change((r) {
                if (v == 'legacySeriesRoute') {
                  return r.copyWith(
                    sourceMode: QuickPlaySourceMode.torrentsThenAddons,
                    preserveLegacyCombinedPackSearch: true,
                  );
                }
                return r.copyWith(
                  sourceMode: QuickPlaySourceMode.values.byName(v),
                  preserveLegacyCombinedPackSearch: false,
                );
              }),
            ),
            _divider(),
            _selectRow(
              icon: Icons.sort_rounded,
              title: 'Result order',
              subtitle: _rankingDescription(_rules.ranking),
              node: _ranking,
              value: _rules.ranking.name,
              options: const [
                SettingsSelectOption('debrify', 'Debrify relevance'),
                SettingsSelectOption('exactOrder', 'Exact provider order'),
                SettingsSelectOption('quality', 'Highest quality first'),
                SettingsSelectOption('smallest', 'Smallest file first'),
                SettingsSelectOption('readyFirst', 'Direct / ready first'),
              ],
              onChanged: (v) => _change(
                (r) => r.copyWith(ranking: QuickPlayRanking.values.byName(v)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _Panel(
        title: 'Matching and safety',
        child: Column(
          children: [
            SettingsToggleTile(
              focusNode: _relax,
              icon: Icons.filter_list_off_rounded,
              title: 'Relax filters when needed',
              subtitle:
                  _rules.ranking == QuickPlayRanking.exactOrder &&
                      _rules.useFilters
                  ? 'Exact order wins; turn this off to exclude mismatches'
                  : 'Fall back gradually instead of failing playback',
              value: _rules.relaxFilters,
              onChanged: (v) => _change((r) => r.copyWith(relaxFilters: v)),
            ),
            if (_rules.ranking == QuickPlayRanking.exactOrder &&
                _rules.useFilters &&
                _rules.relaxFilters) ...[
              _divider(),
              const Padding(
                padding: EdgeInsets.all(12),
                child: SettingsInfoBanner(
                  text:
                      'Exact provider order takes priority. Saved filters do not rearrange that order; turn off filter relaxation to remove non-matches.',
                ),
              ),
            ],
            _divider(),
            SettingsToggleTile(
              focusNode: _validate,
              icon: Icons.verified_rounded,
              title: 'Validate direct links',
              subtitle: 'Skip links with evidence that they are offline',
              value: _rules.validateDirectLinks,
              onChanged: (v) =>
                  _change((r) => r.copyWith(validateDirectLinks: v)),
            ),
            if (_series) ...[
              _divider(),
              _selectRow(
                icon: Icons.layers_rounded,
                title: 'Pack preference',
                subtitle: 'The requested episode is always verified',
                node: _packOrder,
                value: _rules.packPreference.name,
                options: const [
                  SettingsSelectOption(
                    'widestFirst',
                    'Complete → multi-season → season',
                  ),
                  SettingsSelectOption(
                    'seasonFirst',
                    'Season → multi-season → complete',
                  ),
                  SettingsSelectOption(
                    'exactEpisodeOnly',
                    'Exact episode only',
                  ),
                ],
                onChanged: (v) => _change(
                  (r) => r.copyWith(
                    packPreference: QuickPlayPackPreference.values.byName(v),
                    preferSeriesPacks: v != 'exactEpisodeOnly',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      _Panel(
        title: 'Waiting and recovery',
        child: Column(
          children: [
            _selectRow(
              icon: Icons.timer_rounded,
              title: 'Torrent search wait',
              subtitle: _rules.searchTimeoutSeconds == 0
                  ? 'Wait for enabled engines — today\'s behavior'
                  : 'Stop after ${_rules.searchTimeoutSeconds} seconds',
              node: _searchWait,
              value: '${_rules.searchTimeoutSeconds}',
              options: const [
                SettingsSelectOption('0', 'Wait for enabled engines'),
                SettingsSelectOption('5', '5 seconds'),
                SettingsSelectOption('10', '10 seconds'),
                SettingsSelectOption('15', '15 seconds'),
                SettingsSelectOption('20', '20 seconds'),
                SettingsSelectOption('30', '30 seconds'),
              ],
              onChanged: (v) => _change(
                (r) => r.copyWith(searchTimeoutSeconds: int.parse(v)),
              ),
            ),
            _divider(),
            _selectRow(
              icon: Icons.extension_rounded,
              title: 'Each addon wait',
              subtitle: 'Slow addons are skipped after this limit',
              node: _addonWait,
              value: '${_rules.addonTimeoutSeconds}',
              options: const [
                SettingsSelectOption('10', '10 seconds'),
                SettingsSelectOption('15', '15 seconds — today\'s behavior'),
                SettingsSelectOption('20', '20 seconds'),
                SettingsSelectOption('30', '30 seconds'),
                SettingsSelectOption('45', '45 seconds'),
                SettingsSelectOption('60', '60 seconds'),
              ],
              onChanged: (v) =>
                  _change((r) => r.copyWith(addonTimeoutSeconds: int.parse(v))),
            ),
            if (_series) ...[
              _divider(),
              _selectRow(
                icon: Icons.history_rounded,
                title: 'Remember a failed pack search',
                subtitle: 'Avoid repeating an empty pack search',
                node: _packCache,
                value: '${_rules.failedPackCacheHours}',
                options: const [
                  SettingsSelectOption('0', 'Do not remember'),
                  SettingsSelectOption('1', '1 hour'),
                  SettingsSelectOption('6', '6 hours — today\'s behavior'),
                  SettingsSelectOption('12', '12 hours'),
                  SettingsSelectOption('24', '24 hours'),
                ],
                onChanged: (v) => _change(
                  (r) => r.copyWith(failedPackCacheHours: int.parse(v)),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _selectRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required FocusNode node,
    required String value,
    required List<SettingsSelectOption> options,
    required ValueChanged<String> onChanged,
  }) => _SelectRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    child: SettingsSelectDropdown(
      focusNode: node,
      options: options,
      value: value,
      onChanged: onChanged,
    ),
  );

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, color: AppThemeScope.of(context).settings.line),
  );

  Widget _action({
    required FocusNode node,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool expanded = false,
  }) => _ActionRow(
    node: node,
    icon: icon,
    title: title,
    subtitle: subtitle,
    expanded: expanded,
    onTap: onTap,
  );

  void _restore() async {
    await StorageService.restoreQuickPlayDefaults();
    if (!mounted) return;
    setState(() {
      _movie = QuickPlayRules.debrifyDefault(isMovie: true);
      _show = QuickPlayRules.debrifyDefault(isMovie: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restored today\'s Quick Play behavior')),
    );
  }
}
