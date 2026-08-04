import 'package:flutter/material.dart';
import '../../utils/tv_reveal.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/storage_service.dart';
import '../../services/analytics_service.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/home/home_theme.dart';

/// Full-screen DPAD-first Home-row manager — a two-pane "group → item" filter,
/// modelled on the Stremio TV channel filter's grammar but 2 levels deep (no
/// genre wall). The left rail lists groups (Continue Watching, Trakt, Simkl,
/// Favorites, then each catalog addon); the right pane lists that group's rows
/// as on/off toggles. Header actions: All on / All off / Invert.
///
/// Persists the same disabled-id set the Home board reads
/// ([StorageService.setHomeDisabledSections]): fixed leaves like `cw:movies`,
/// `trakt:shows`, `fav:iptv`, and catalog leaves `addonId:type:catalogId`. On
/// save the set is regenerated from leaf state (only OFF rows are stored).
class HomeSectionsFilterPage extends StatefulWidget {
  /// The board's catalog addons with their browsable catalogs, in board order.
  final List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>
      catalogTree;
  final Set<String> disabled;
  final bool isTelevision;

  const HomeSectionsFilterPage({
    super.key,
    required this.catalogTree,
    required this.disabled,
    required this.isTelevision,
  });

  @override
  State<HomeSectionsFilterPage> createState() => _HomeSectionsFilterPageState();
}

/// One toggleable Home row.
class _Item {
  final String id;
  final String label;
  final String? badge; // catalog type badge (MOVIE/SERIES/…); null for fixed
  bool on;
  _Item(this.id, this.label, this.on, {this.badge});
}

/// A rail group whose items are the rows shown under it.
class _Group {
  final String name;
  final List<_Item> items;
  _Group(this.name, this.items);

  int get onCount => items.where((it) => it.on).length;
  int get total => items.length;
}

class _HomeSectionsFilterPageState extends State<HomeSectionsFilterPage> {
  static const Color _onColor = Color(0xFF34D399);
  static const Color _offColor = Color(0xFF4B465F);

  late final List<_Group> _groups;
  int _selectedGroup = 0;
  int _selectedItem = 0;
  bool _changed = false;
  bool _saved = false;

  final List<FocusNode> _headerNodes =
      List.generate(3, (i) => FocusNode(debugLabel: 'homeHeader$i'));
  List<FocusNode> _railNodes = [];
  List<FocusNode> _listNodes = [];

  /// Where a down-press from the header should land back.
  (String, int) _headerReturn = ('rail', 0);
  String _area = 'rail';

  /// Narrow (phone) layout: one pane at a time.
  bool _narrow = false;
  bool _narrowList = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('home_sections_filter');
    _groups = _buildModel();
    _railNodes = List.generate(
      _groups.length,
      (i) => FocusNode(debugLabel: 'homeRail$i'),
    );
    _rebuildListNodes();
    // Land focus on the first rail group so DPAD works the moment the page
    // opens (this post-frame fires — the first build schedules a frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_railNodes.isNotEmpty) {
        _railNodes.first.requestFocus();
      } else {
        _headerNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final n in _headerNodes) {
      n.dispose();
    }
    for (final n in _railNodes) {
      n.dispose();
    }
    for (final n in _listNodes) {
      n.dispose();
    }
    super.dispose();
  }

  List<_Group> _buildModel() {
    final d = widget.disabled;
    bool on(String id) => !d.contains(id);

    final groups = <_Group>[
      _Group('Continue Watching', [
        _Item('cw:movies', 'Movies', on('cw:movies')),
        _Item('cw:series', 'Series', on('cw:series')),
      ]),
      _Group('Trakt', [
        _Item('trakt:movies', 'Movies', on('trakt:movies')),
        _Item('trakt:shows', 'Shows', on('trakt:shows')),
      ]),
      _Group('Simkl', [
        _Item('simkl:movies', 'Movies', on('simkl:movies')),
        _Item('simkl:shows', 'Shows', on('simkl:shows')),
      ]),
      _Group('IPTV Continue Watching', [
        _Item('iptv:movies', 'Movies', on('iptv:movies')),
        _Item('iptv:series', 'Series', on('iptv:series')),
      ]),
      _Group('Favorites', [
        _Item('fav:playlist', 'Playlist', on('fav:playlist')),
        _Item('fav:debrify', 'Debrify TV', on('fav:debrify')),
        _Item('fav:stremio', 'Stremio TV', on('fav:stremio')),
        _Item('fav:iptv', 'IPTV', on('fav:iptv')),
      ]),
    ];

    for (final entry in widget.catalogTree) {
      final addon = entry.addon;
      if (entry.catalogs.isEmpty) continue;
      groups.add(_Group(
        addon.name,
        [
          for (final c in entry.catalogs)
            _Item(
              '${addon.id}:${c.type}:${c.id}',
              c.name,
              on('${addon.id}:${c.type}:${c.id}'),
              badge: c.type,
            ),
        ],
      ));
    }
    return groups;
  }

  (int, int) get _totals {
    var on = 0, total = 0;
    for (final g in _groups) {
      on += g.onCount;
      total += g.total;
    }
    return (on, total);
  }

  Future<void> _persist() async {
    if (!_changed || _saved) return;
    _saved = true;
    // Store only the OFF rows (empty set = everything shown → key removed).
    final out = <String>{};
    for (final g in _groups) {
      for (final it in g.items) {
        if (!it.on) out.add(it.id);
      }
    }
    await StorageService.setHomeDisabledSections(out);
  }

  // ── Mutations ──────────────────────────────────────────────────────────────
  void _mutate(VoidCallback fn) {
    setState(() {
      _changed = true;
      _saved = false;
      fn();
    });
  }

  // Header actions target the SELECTED group's rows (the 2nd pane), not every
  // group — scoped so "All off" clears just the group you're looking at.
  void _setCurrentGroup(bool v) => _mutate(() {
        for (final it in _groups[_selectedGroup].items) {
          it.on = v;
        }
      });

  void _invertCurrentGroup() => _mutate(() {
        for (final it in _groups[_selectedGroup].items) {
          it.on = !it.on;
        }
      });

  /// Not-all-on → all on; all-on → all off (matches the TV filter).
  void _toggleGroup(int i) => _mutate(() {
        final g = _groups[i];
        final v = g.onCount != g.total;
        for (final it in g.items) {
          it.on = v;
        }
      });

  void _toggleItem(_Item it) => _mutate(() => it.on = !it.on);

  // ── Focus plumbing ───────────────────────────────────────────────────────
  void _rebuildListNodes() {
    for (final n in _listNodes) {
      n.dispose();
    }
    _listNodes = List.generate(
      _groups.isEmpty ? 0 : _groups[_selectedGroup].items.length,
      (i) => FocusNode(debugLabel: 'homeList$i'),
    );
  }

  void _selectGroup(int i) {
    if (i == _selectedGroup) return;
    setState(() {
      _selectedGroup = i;
      _selectedItem = 0;
      _rebuildListNodes();
    });
  }

  void _focusAfterFrame(FocusNode node) {
    // Focus NOW if the node is already mounted (wide layout builds both panes);
    // a bare post-frame callback never fires when switching panes schedules no
    // rebuild, stranding DPAD focus on the current pane. Narrow mode setState()s
    // to build the target pane first, so defer to post-frame until it mounts.
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _showListPane({int? focusIndex}) {
    if (_narrow && !_narrowList) setState(() => _narrowList = true);
    if (focusIndex != null && _listNodes.isNotEmpty) {
      _focusAfterFrame(_listNodes[focusIndex.clamp(0, _listNodes.length - 1)]);
    }
  }

  void _showRailPane() {
    if (_narrow && _narrowList) setState(() => _narrowList = false);
    if (_railNodes.isNotEmpty) _focusAfterFrame(_railNodes[_selectedGroup]);
  }

  void _ensureVisible(FocusNode node) {
    final ctx = node.context;
    if (ctx == null) return;
    tvRevealMinimal(ctx, duration: const Duration(milliseconds: 120));
  }

  // ── DPAD handlers ────────────────────────────────────────────────────────
  KeyEventResult _headerKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (i > 0) _headerNodes[i - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (i < _headerNodes.length - 1) _headerNodes[i + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_narrow) {
        if (_narrowList && _listNodes.isNotEmpty) {
          _listNodes[_selectedItem.clamp(0, _listNodes.length - 1)]
              .requestFocus();
        } else if (_railNodes.isNotEmpty) {
          _railNodes[_selectedGroup].requestFocus();
        }
        return KeyEventResult.handled;
      }
      final (area, index) = _headerReturn;
      if (area == 'list' && index < _listNodes.length) {
        _listNodes[index].requestFocus();
      } else if (_railNodes.isNotEmpty) {
        _railNodes[index.clamp(0, _railNodes.length - 1)].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
    if (isActivateKey(k)) {
      switch (i) {
        case 0:
          _setCurrentGroup(true);
        case 1:
          _setCurrentGroup(false);
        case 2:
          _invertCurrentGroup();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _railKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (i < _railNodes.length - 1) {
        _selectGroup(i + 1);
        _railNodes[i + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (i == 0) {
        if (e is KeyDownEvent) {
          _headerReturn = ('rail', 0);
          _headerNodes.first.requestFocus();
        }
      } else {
        _selectGroup(i - 1);
        _railNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.arrowRight) {
      _showListPane(focusIndex: _selectedItem);
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      _toggleGroup(i);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _listKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final items = _groups[_selectedGroup].items;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (i < items.length - 1) {
        _selectedItem = i + 1;
        _listNodes[i + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (i == 0) {
        if (e is KeyDownEvent) {
          _headerReturn = ('list', 0);
          _headerNodes.first.requestFocus();
        }
      } else {
        _selectedItem = i - 1;
        _listNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack) {
      _showRailPane();
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      _toggleItem(items[i]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  Future<void> _saveAndClose() async {
    await _persist();
    if (mounted) Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    final (on, total) = _totals;
    _narrow = MediaQuery.sizeOf(context).width < 640;
    if (!_narrow) _narrowList = false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if ((_narrowList || _area == 'list') && _railNodes.isNotEmpty) {
          _showRailPane();
        } else {
          _saveAndClose();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: HomeTheme.pageBackground,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(on, total),
                Expanded(child: _buildPanes()),
                if (widget.isTelevision) _buildHintBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int on, int total) {
    final backButton = IconButton(
      onPressed: _saveAndClose,
      icon: Icon(Icons.arrow_back_rounded,
          color: Colors.white.withValues(alpha: 0.7)),
    );
    const title = Text(
      'Home Screen',
      style: TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
    final countPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$on',
            style: const TextStyle(
                color: _onColor, fontWeight: FontWeight.w800),
          ),
          TextSpan(text: _narrow ? ' / $total on' : ' / $total rows on'),
        ]),
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65), fontSize: 12.5),
      ),
    );
    if (_narrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [backButton, const SizedBox(width: 4), title]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  countPill,
                  _actionButton(0, 'All on'),
                  _actionButton(1, 'All off'),
                  _actionButton(2, 'Invert'),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          backButton,
          const SizedBox(width: 4),
          title,
          const SizedBox(width: 14),
          countPill,
          const Spacer(),
          _actionButton(0, 'All on'),
          const SizedBox(width: 8),
          _actionButton(1, 'All off'),
          const SizedBox(width: 8),
          _actionButton(2, 'Invert'),
        ],
      ),
    );
  }

  Widget _actionButton(int i, String label) {
    final node = _headerNodes[i];
    return Focus(
      focusNode: node,
      onFocusChange: (f) {
        if (f) {
          _area = 'header';
          _ensureVisible(node);
        }
      },
      onKeyEvent: (_, e) => _headerKey(i, e),
      child: ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          final focused = node.hasFocus;
          return GestureDetector(
            onTap: () {
              switch (i) {
                case 0:
                  _setCurrentGroup(true);
                case 1:
                  _setCurrentGroup(false);
                case 2:
                  _invertCurrentGroup();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: focused
                      ? HomeTheme.focusGold
                      : Colors.white.withValues(alpha: 0.16),
                  width: focused ? 2 : 1,
                ),
                // Bloom only off-TV — an animated/static blur shadow re-rasters
                // on every focus move and janks weak TV GPUs (perf playbook).
                boxShadow: focused && !widget.isTelevision
                    ? [
                        BoxShadow(
                          color:
                              HomeTheme.focusGoldDeep.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: focused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPanes() {
    if (_narrow) {
      if (!_narrowList) return _buildRail();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNarrowBreadcrumb(),
          Expanded(child: _buildItemList()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _buildRail()),
        Container(width: 0.5, color: Colors.white.withValues(alpha: 0.07)),
        Expanded(child: _buildItemList()),
      ],
    );
  }

  Widget _buildNarrowBreadcrumb() {
    final g = _groups[_selectedGroup];
    return GestureDetector(
      onTap: _showRailPane,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        child: Row(
          children: [
            Icon(Icons.chevron_left_rounded,
                size: 18, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                g.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 12),
      itemCount: _groups.length,
      itemBuilder: (context, i) {
        final g = _groups[i];
        final node = _railNodes[i];
        return Focus(
          focusNode: node,
          onFocusChange: (f) {
            if (f) {
              _area = 'rail';
              _ensureVisible(node);
            }
          },
          onKeyEvent: (_, e) => _railKey(i, e),
          child: ListenableBuilder(
            listenable: node,
            builder: (context, _) {
              final focused = node.hasFocus;
              final selected = i == _selectedGroup;
              return GestureDetector(
                onTap: () {
                  _selectGroup(i);
                  if (_narrow) {
                    _showListPane(focusIndex: 0);
                  } else {
                    node.requestFocus();
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? HomeTheme.chromeAccent.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          focused ? HomeTheme.focusGold : Colors.transparent,
                      width: focused ? 2 : 1.5,
                    ),
                    boxShadow: focused && !widget.isTelevision
                        ? [
                            BoxShadow(
                              color: HomeTheme.focusGoldDeep
                                  .withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      _stateDot(g.onCount, g.total),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: focused || selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.72),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${g.onCount}/${g.total}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (focused || _narrow) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.6)),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildItemList() {
    final items = _groups[_selectedGroup].items;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 18, 12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        final node = _listNodes[i];
        return Focus(
          focusNode: node,
          onFocusChange: (f) {
            if (f) {
              _area = 'list';
              _ensureVisible(node);
            }
          },
          onKeyEvent: (_, e) => _listKey(i, e),
          child: ListenableBuilder(
            listenable: node,
            builder: (context, _) {
              final focused = node.hasFocus;
              return GestureDetector(
                onTap: () {
                  _selectedItem = i;
                  node.requestFocus();
                  _toggleItem(it);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: focused
                          ? HomeTheme.focusGold
                          : Colors.white.withValues(alpha: 0.05),
                      width: focused ? 2 : 1.5,
                    ),
                    boxShadow: focused && !widget.isTelevision
                        ? [
                            BoxShadow(
                              color: HomeTheme.focusGoldDeep
                                  .withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                it.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (it.badge != null) ...[
                              const SizedBox(width: 8),
                              _typeBadge(it.badge!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _switchPill(it.on),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _stateDot(int on, int total) {
    final Color color;
    Gradient? gradient;
    if (on == 0) {
      color = _offColor;
    } else if (on == total) {
      color = _onColor;
    } else {
      color = Colors.transparent;
      gradient = const LinearGradient(
        colors: [_onColor, _offColor],
        stops: [0.5, 0.5],
      );
    }
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
          color: color, gradient: gradient, shape: BoxShape.circle),
    );
  }

  Widget _switchPill(bool isOn) {
    return Container(
      width: 38,
      height: 21,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: isOn ? HomeTheme.chromeAccent : _offColor,
        borderRadius: BorderRadius.circular(99),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _typeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: HomeTheme.chromeAccent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: HomeTheme.chromeAccent.withValues(alpha: 0.95),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildHintBar() {
    const hints = [
      ('↑↓', 'move'),
      ('←→', 'switch pane'),
      ('OK', 'toggle'),
      ('BACK', 'back a level · saves & closes from groups'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.07), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (key, label) in hints) ...[
            Container(
              margin: const EdgeInsets.only(left: 18),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                key,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
