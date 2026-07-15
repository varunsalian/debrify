import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/storage_service.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/home/home_theme.dart';

/// Full-screen DPAD-first channel filter — the "Two-Pane Manager".
///
/// Vertical = move, horizontal = structure: addons in a left rail with live
/// on/mixed/off state, catalogs as big switch rows on the right, and genres
/// opening as a 2-D chip wall (a few hundred genres is ~20 grid steps, not
/// ~300 list steps like the old checkbox tree). The header action row
/// (All on / All off / Invert) is one arrow-up away from any list top.
///
/// Storage-compatible with the old dialog: persists the same
/// [StorageService.setStremioTvDisabledFilters] id set (addon id, catalog id
/// `addon:catalog:type`, genre id `addon:catalog:type:genre`). On save the
/// set is regenerated from leaf state, which also normalizes any stale
/// parent-level ids left behind by the old sheet.
class StremioTvFilterPage extends StatefulWidget {
  final List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>
      filterTree;
  final Set<String> disabledFilters;
  final bool isTelevision;

  const StremioTvFilterPage({
    super.key,
    required this.filterTree,
    required this.disabledFilters,
    required this.isTelevision,
  });

  @override
  State<StremioTvFilterPage> createState() => _StremioTvFilterPageState();
}

/// A catalog with its per-leaf enabled state. A catalog with genres has one
/// leaf per genre; a catalog without genres is itself the single leaf.
class _FilterCatalog {
  final String id;
  final String name;
  final String type;
  final List<String> genres;
  final List<bool> on;

  _FilterCatalog({
    required this.id,
    required this.name,
    required this.type,
    required this.genres,
    required this.on,
  });

  bool get hasGenres => genres.isNotEmpty;
  int get onCount => on.where((v) => v).length;
  int get total => on.length;
  String genreId(int i) => '$id:${genres[i]}';
}

class _FilterAddon {
  final String id;
  final String name;
  final List<_FilterCatalog> cats;

  _FilterAddon({required this.id, required this.name, required this.cats});

  (int, int) get counts {
    var on = 0, total = 0;
    for (final c in cats) {
      on += c.onCount;
      total += c.total;
    }
    return (on, total);
  }
}

class _StremioTvFilterPageState extends State<StremioTvFilterPage> {
  static const Color _onColor = Color(0xFF34D399);
  static const Color _offColor = Color(0xFF4B465F);

  late final List<_FilterAddon> _addons;
  int _selectedAddon = 0;
  int _selectedCat = 0;
  _FilterCatalog? _wall;
  int _wallCols = 4;
  bool _changed = false;
  bool _saved = false;

  final List<FocusNode> _headerNodes =
      List.generate(3, (i) => FocusNode(debugLabel: 'filterHeader$i'));
  List<FocusNode> _railNodes = [];
  List<FocusNode> _listNodes = [];
  final List<FocusNode> _wallActionNodes =
      List.generate(3, (i) => FocusNode(debugLabel: 'wallAction$i'));
  List<FocusNode> _wallChipNodes = [];

  /// Where a down-press from the header actions should land (the area the
  /// focus came up from), so header round-trips don't teleport.
  (String, int) _headerReturn = ('rail', 0);

  /// Which area currently holds focus ('rail' | 'list' | 'header'), kept by
  /// the rows' onFocusChange. BACK walks the hierarchy with it: genre wall →
  /// catalog list → addon rail → save & close, instead of closing the whole
  /// page from anywhere.
  String _area = 'rail';

  /// Narrow (phone / small window) layout: the 300px rail + list Row doesn't
  /// fit, so the page shows ONE pane at a time and drills down instead.
  /// [_narrow] is refreshed from the window width on every build;
  /// [_narrowList] is true while the catalog list is the visible pane.
  bool _narrow = false;
  bool _narrowList = false;

  @override
  void initState() {
    super.initState();
    _addons = _buildModel();
    _railNodes = List.generate(
      _addons.length,
      (i) => FocusNode(debugLabel: 'filterRail$i'),
    );
    _rebuildListNodes();
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
    for (final n in _wallActionNodes) {
      n.dispose();
    }
    for (final n in _wallChipNodes) {
      n.dispose();
    }
    super.dispose();
  }

  // ==========================================================================
  // Model
  // ==========================================================================

  List<_FilterAddon> _buildModel() {
    final disabled = widget.disabledFilters;
    return widget.filterTree.map((entry) {
      final addon = entry.addon;
      final cats = entry.catalogs.map((catalog) {
        final catalogId = '${addon.id}:${catalog.id}:${catalog.type}';
        final genres = catalog.genreOptions;
        final List<bool> on;
        if (genres.isEmpty) {
          on = [
            !(disabled.contains(catalogId) || disabled.contains(addon.id)),
          ];
        } else {
          on = genres
              .map(
                (g) => !(disabled.contains('$catalogId:$g') ||
                    disabled.contains(catalogId) ||
                    disabled.contains(addon.id)),
              )
              .toList();
        }
        return _FilterCatalog(
          id: catalogId,
          name: catalog.name,
          type: catalog.type,
          genres: genres,
          on: on,
        );
      }).toList();
      return _FilterAddon(id: addon.id, name: addon.name, cats: cats);
    }).toList();
  }

  (int, int) get _totals {
    var on = 0, total = 0;
    for (final a in _addons) {
      final (o, t) = a.counts;
      on += o;
      total += t;
    }
    return (on, total);
  }

  Future<void> _persist() async {
    if (!_changed || _saved) return;
    _saved = true;
    final out = <String>{};
    for (final a in _addons) {
      var addonAllOff = true;
      for (final c in a.cats) {
        if (c.hasGenres) {
          var catAllOff = true;
          for (var i = 0; i < c.genres.length; i++) {
            if (!c.on[i]) {
              out.add(c.genreId(i));
            } else {
              catAllOff = false;
            }
          }
          if (catAllOff) {
            out.add(c.id);
          } else {
            addonAllOff = false;
          }
        } else {
          if (!c.on[0]) {
            out.add(c.id);
          } else {
            addonAllOff = false;
          }
        }
      }
      if (addonAllOff && a.cats.isNotEmpty) out.add(a.id);
    }
    await StorageService.setStremioTvDisabledFilters(out);
  }

  // ==========================================================================
  // Mutations (all mark _changed)
  // ==========================================================================

  void _mutate(VoidCallback fn) {
    setState(() {
      _changed = true;
      _saved = false;
      fn();
    });
  }

  void _setEverything(bool v) => _mutate(() {
        for (final a in _addons) {
          for (final c in a.cats) {
            c.on.fillRange(0, c.on.length, v);
          }
        }
      });

  void _invertEverything() => _mutate(() {
        for (final a in _addons) {
          for (final c in a.cats) {
            for (var i = 0; i < c.on.length; i++) {
              c.on[i] = !c.on[i];
            }
          }
        }
      });

  /// Not-all-on → all on; all-on → all off (matches the prototype).
  void _toggleAddon(int i) => _mutate(() {
        final a = _addons[i];
        final (on, total) = a.counts;
        final v = on != total;
        for (final c in a.cats) {
          c.on.fillRange(0, c.on.length, v);
        }
      });

  void _toggleCatalog(_FilterCatalog c) => _mutate(() {
        final v = c.onCount != c.total;
        c.on.fillRange(0, c.on.length, v);
      });

  // ==========================================================================
  // Focus plumbing
  // ==========================================================================

  void _rebuildListNodes() {
    for (final n in _listNodes) {
      n.dispose();
    }
    _listNodes = List.generate(
      _addons.isEmpty ? 0 : _addons[_selectedAddon].cats.length,
      (i) => FocusNode(debugLabel: 'filterList$i'),
    );
  }

  void _selectAddon(int i) {
    if (i == _selectedAddon) return;
    setState(() {
      _selectedAddon = i;
      _selectedCat = 0;
      _rebuildListNodes();
    });
  }

  void _focusAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  /// Moves to the catalog list. In narrow mode this swaps the visible pane
  /// first, so the target node has a context to focus (post-frame).
  void _showListPane({int? focusIndex}) {
    if (_narrow && !_narrowList) setState(() => _narrowList = true);
    if (focusIndex != null && _listNodes.isNotEmpty) {
      _focusAfterFrame(
        _listNodes[focusIndex.clamp(0, _listNodes.length - 1)],
      );
    }
  }

  /// Moves back to the addon rail (swapping panes in narrow mode).
  void _showRailPane() {
    if (_narrow && _narrowList) setState(() => _narrowList = false);
    if (_railNodes.isNotEmpty) _focusAfterFrame(_railNodes[_selectedAddon]);
  }

  void _openWall(_FilterCatalog c) {
    setState(() {
      _wall = c;
      for (final n in _wallChipNodes) {
        n.dispose();
      }
      _wallChipNodes = List.generate(
        c.genres.length,
        (i) => FocusNode(debugLabel: 'wallChip$i'),
      );
    });
    if (_wallChipNodes.isNotEmpty) _focusAfterFrame(_wallChipNodes.first);
  }

  void _closeWall() {
    if (_wall == null) return;
    setState(() => _wall = null);
    if (_selectedCat < _listNodes.length) {
      _focusAfterFrame(_listNodes[_selectedCat]);
    }
  }

  void _ensureVisible(FocusNode node) {
    final ctx = node.context;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 120),
    );
  }

  // ==========================================================================
  // DPAD handlers
  // ==========================================================================

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
      // Narrow mode: land on whichever pane is actually visible — the
      // remembered return area may belong to the hidden pane.
      if (_narrow) {
        if (_narrowList && _listNodes.isNotEmpty) {
          _listNodes[_selectedCat.clamp(0, _listNodes.length - 1)]
              .requestFocus();
        } else if (_railNodes.isNotEmpty) {
          _railNodes[_selectedAddon].requestFocus();
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
          _setEverything(true);
        case 1:
          _setEverything(false);
        case 2:
          _invertEverything();
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
        _selectAddon(i + 1);
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
        _selectAddon(i - 1);
        _railNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.arrowRight) {
      _showListPane(focusIndex: _selectedCat);
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      _toggleAddon(i);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _listKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final cats = _addons[_selectedAddon].cats;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (i < cats.length - 1) {
        _selectedCat = i + 1;
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
        _selectedCat = i - 1;
        _listNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack) {
      // BACK from the catalog list steps out to the rail (platforms where
      // back arrives as a key event; system back goes through the PopScope).
      _showRailPane();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      final c = cats[i];
      if (c.hasGenres) {
        _selectedCat = i;
        _openWall(c);
      }
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      _toggleCatalog(cats[i]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _wallActionKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (i > 0) {
        _wallActionNodes[i - 1].requestFocus();
      } else {
        _closeWall();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (i < 2) _wallActionNodes[i + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_wallChipNodes.isNotEmpty) _wallChipNodes.first.requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      _closeWall();
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      final c = _wall!;
      _mutate(() {
        for (var g = 0; g < c.on.length; g++) {
          c.on[g] = i == 0 ? true : (i == 1 ? false : !c.on[g]);
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _wallChipKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final n = _wallChipNodes.length;
    if (k == LogicalKeyboardKey.arrowRight) {
      if (i < n - 1) _wallChipNodes[i + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (i % _wallCols == 0) {
        if (e is KeyDownEvent) _closeWall();
      } else {
        _wallChipNodes[i - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _wallChipNodes[(i + _wallCols).clamp(0, n - 1)].requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (i < _wallCols) {
        if (e is KeyDownEvent) _wallActionNodes.first.requestFocus();
      } else {
        _wallChipNodes[i - _wallCols].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      _closeWall();
      return KeyEventResult.handled;
    }
    if (isActivateKey(k)) {
      final c = _wall!;
      _mutate(() => c.on[i] = !c.on[i]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  /// Persist BEFORE popping so the caller can re-read storage the moment the
  /// route returns (an un-awaited save on pop races that read), and return
  /// whether anything changed.
  Future<void> _saveAndClose() async {
    await _persist();
    if (mounted) Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    final (on, total) = _totals;
    _narrow = MediaQuery.sizeOf(context).width < 640;
    // A resize back to wide shows both panes again; drop the stale flag so
    // BACK doesn't detour through _showRailPane.
    if (!_narrow) _narrowList = false;
    return PopScope(
      // Back always routes through here and walks one level at a time:
      // genre wall → catalog list → addon rail → save & close.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_wall != null) {
          _closeWall();
        } else if ((_narrowList || _area == 'list') && _railNodes.isNotEmpty) {
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
                Expanded(
                  child: _addons.isEmpty
                      ? Center(
                          child: Text(
                            'No addons with catalogs found.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 15,
                            ),
                          ),
                        )
                      : (_wall == null ? _buildPanes() : _buildWall(_wall!)),
                ),
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
      // Explicit close affordance: skip the hierarchical BACK walk
      // (maybePop would step list→rail first), just close the wall if
      // open, then save & leave.
      onPressed: () {
        if (_wall != null) {
          _closeWall();
        } else {
          _saveAndClose();
        }
      },
      icon: Icon(
        Icons.arrow_back_rounded,
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );
    const title = Text(
      'Channel Filters',
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
        TextSpan(
          children: [
            TextSpan(
              text: '$on',
              style: const TextStyle(
                color: _onColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            // Narrow header trades the label for space.
            TextSpan(text: _narrow ? ' / $total on' : ' / $total channels on'),
          ],
        ),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.65),
          fontSize: 12.5,
        ),
      ),
    );
    // Narrow: the single Row overflows, so stack — title line, then the
    // count pill and actions wrapping onto as many lines as they need.
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
                  _setEverything(true);
                case 1:
                  _setEverything(false);
                case 2:
                  _invertEverything();
              }
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: focused
                      ? HomeTheme.focusGold
                      : Colors.white.withValues(alpha: 0.16),
                  width: focused ? 2 : 1,
                ),
                boxShadow: focused
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

  // ─── Two panes ────────────────────────────────────────────────────────────

  Widget _buildPanes() {
    // Narrow: one pane at a time — the rail, or the selected addon's
    // catalogs behind a breadcrumb.
    if (_narrow) {
      if (!_narrowList) return _buildRail();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNarrowBreadcrumb(),
          Expanded(child: _buildCatalogList()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _buildRail()),
        Container(width: 0.5, color: Colors.white.withValues(alpha: 0.07)),
        Expanded(child: _buildCatalogList()),
      ],
    );
  }

  /// Narrow-mode header above the catalog list: tappable "‹ addon" trail
  /// back to the rail (DPAD users get there with LEFT/BACK).
  Widget _buildNarrowBreadcrumb() {
    final a = _addons[_selectedAddon];
    return GestureDetector(
      onTap: _showRailPane,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        child: Row(
          children: [
            Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                a.name,
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
      itemCount: _addons.length,
      itemBuilder: (context, i) {
        final a = _addons[i];
        final (on, total) = a.counts;
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
              final selected = i == _selectedAddon;
              return GestureDetector(
                onTap: () {
                  _selectAddon(i);
                  if (_narrow) {
                    // Tap drills into the addon's catalogs on small screens.
                    _showListPane(focusIndex: 0);
                  } else {
                    node.requestFocus();
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? HomeTheme.chromeAccent.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: focused
                          ? HomeTheme.focusGold
                          : Colors.transparent,
                      width: focused ? 2 : 1.5,
                    ),
                    boxShadow: focused
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
                      _stateDot(on, total),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          a.name,
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
                        '$on/$total',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      // Focused cue: right opens this addon's catalogs.
                      // Always shown when narrow — tap drills in there.
                      if (focused || _narrow) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
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

  /// Small glassy affordance (same language as the dial's OPTIONS chip)
  /// telling the user RIGHT opens this catalog's genre wall.
  Widget _genresHintChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.keyboard_arrow_right_rounded,
            size: 12,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 3),
          Text(
            'GENRES',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Touch affordance for opening a catalog's genre wall: a small bordered
  /// chip that reads as a button (fill + outline + chevron), unlike the old
  /// bare "▸ genres" text which looked like a status label.
  Widget _genresButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: HomeTheme.chromeAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: HomeTheme.chromeAccent.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Genres',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: 15,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogList() {
    final cats = _addons[_selectedAddon].cats;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 18, 12),
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final c = cats[i];
        final node = _listNodes[i];
        final on = c.onCount;
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
                  _selectedCat = i;
                  node.requestFocus();
                  _toggleCatalog(c);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: focused
                          ? HomeTheme.focusGold
                          : Colors.white.withValues(alpha: 0.05),
                      width: focused ? 2 : 1.5,
                    ),
                    boxShadow: focused
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _typeBadge(c.type),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.hasGenres
                                  ? '$on of ${c.total} genres on'
                                  : (on > 0 ? 'on' : 'off'),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.42),
                                fontSize: 11,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (c.hasGenres)
                        GestureDetector(
                          onTap: () {
                            _selectedCat = i;
                            _openWall(c);
                          },
                          // Opaque so the padding counts toward the tap
                          // target, not just the painted chip.
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
                            // TV: quiet label, upgraded to the glassy
                            // "▸ GENRES" chip on the focused row (RIGHT opens
                            // it). Touch: a bordered button-looking chip on
                            // every row, so users know it's tappable.
                            child: widget.isTelevision
                                ? (focused
                                      ? _genresHintChip()
                                      : Text(
                                          '▸ genres',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.42),
                                            fontSize: 11,
                                          ),
                                        ))
                                : _genresButton(),
                          ),
                        ),
                      _switchPill(on, c.total),
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

  // ─── Genre wall ───────────────────────────────────────────────────────────

  Widget _buildWall(_FilterCatalog c) {
    final addon = _addons[_selectedAddon];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${addon.name} ▸ '),
                TextSpan(
                  text: '${c.name} (${c.type})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' · ${c.onCount}/${c.total} on'),
              ],
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          child: Row(
            children: [
              _wallAction(0, 'All on'),
              const SizedBox(width: 8),
              _wallAction(1, 'All off'),
              const SizedBox(width: 8),
              _wallAction(2, 'Invert'),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _wallCols = (constraints.maxWidth / 200).floor().clamp(2, 6);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _wallCols,
                  mainAxisExtent: 44,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: c.genres.length,
                itemBuilder: (context, i) => _wallChip(c, i),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _wallAction(int i, String label) {
    final node = _wallActionNodes[i];
    return Focus(
      focusNode: node,
      onKeyEvent: (_, e) => _wallActionKey(i, e),
      child: ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          final focused = node.hasFocus;
          return GestureDetector(
            onTap: () {
              final c = _wall!;
              _mutate(() {
                for (var g = 0; g < c.on.length; g++) {
                  c.on[g] = i == 0 ? true : (i == 1 ? false : !c.on[g]);
                }
              });
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: focused
                      ? HomeTheme.focusGold
                      : Colors.white.withValues(alpha: 0.16),
                  width: focused ? 2 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: focused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.65),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _wallChip(_FilterCatalog c, int i) {
    final node = _wallChipNodes[i];
    return Focus(
      focusNode: node,
      onFocusChange: (f) {
        if (f) _ensureVisible(node);
      },
      onKeyEvent: (_, e) => _wallChipKey(i, e),
      child: ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          final focused = node.hasFocus;
          final on = c.on[i];
          return GestureDetector(
            onTap: () {
              node.requestFocus();
              _mutate(() => c.on[i] = !c.on[i]);
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? HomeTheme.chromeAccent.withValues(alpha: 0.28)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused
                      ? HomeTheme.focusGold
                      : (on
                          ? HomeTheme.chromeAccent.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.12)),
                  width: focused ? 2 : 1.5,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color:
                              HomeTheme.focusGoldDeep.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                c.genres[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: on || focused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.45),
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

  // ─── Small pieces ─────────────────────────────────────────────────────────

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
        color: color,
        gradient: gradient,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _switchPill(int on, int total) {
    final bool isOn = on == total && total > 0;
    final bool isMixed = on > 0 && on < total;
    return Container(
      width: 38,
      height: 21,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: isOn
            ? HomeTheme.chromeAccent
            : (isMixed
                ? HomeTheme.chromeAccent.withValues(alpha: 0.45)
                : _offColor),
        borderRadius: BorderRadius.circular(99),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        alignment: isOn
            ? Alignment.centerRight
            : (isMixed ? Alignment.center : Alignment.centerLeft),
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
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
    final inWall = _wall != null;
    final hints = inWall
        ? const [
            ('↑↓←→', 'move the wall'),
            ('OK', 'toggle genre'),
            ('BACK', 'back to catalogs'),
          ]
        : const [
            ('↑↓', 'move'),
            ('←→', 'switch pane'),
            ('OK', 'toggle · ▸ opens genres'),
            ('BACK', 'back a level · saves & closes from addons'),
          ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.07),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (key, label) in hints) ...[
            Container(
              margin: const EdgeInsets.only(left: 18),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                color: Colors.white.withValues(alpha: 0.38),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
