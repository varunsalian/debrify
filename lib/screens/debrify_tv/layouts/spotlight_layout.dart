import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../models/debrify_tv/channel_stats.dart';
import '../../../models/debrify_tv_cache.dart' show DebrifyTvCacheStatus;
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/tv_text_field.dart';
import 'debrify_tv_view.dart';
import 'spotlight_phone.dart';
import 'spotlight_rail.dart';
import 'spotlight_stage.dart';

/// The Spotlight Debrify TV layout (`debrify_tv_style` = `spotlight`).
///
/// Resolves the device class INSIDE the style, like `detail_page_style` does:
/// television is tested before anything else — a 1920×1080 TV is 960×540
/// logical, and a width-only check would send it to a touch arm.
///
/// The mock at `dev/design/mockups/debrify_tv_spotlight_mockup/` is the spec;
/// every number is logical (÷2 of its 1920×1080 canvas).
class SpotlightLayout extends StatelessWidget {
  final DebrifyTvView view;
  final double bottomInset;

  /// The screen's sidebar-handoff node (`_quickPlayFocusNode`): the shell's
  /// content-focus handler targets it, so the TV arm mounts it on its Quick
  /// Play row and entry focus keeps working under either style.
  final FocusNode entryFocusNode;

  const SpotlightLayout({
    super.key,
    required this.view,
    required this.bottomInset,
    required this.entryFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    // TELEVISION FIRST, before any width test — `resolveDetailSize`'s rule:
    // a 1920×1080 panel is 960×540 logical, and a width-only check would
    // send it to the touch arm.
    if (PlatformUtil.isTelevision) {
      return _SpotlightTvArm(
        view: view,
        bottomInset: bottomInset,
        entryFocusNode: entryFocusNode,
        isTelevision: true,
      );
    }
    // Everything else is a touch/pointer surface: a phone gets a phone — a
    // list and a channel sheet, not a wall of DPAD targets.
    return SpotlightPhoneArm(view: view, bottomInset: bottomInset);
  }
}

/// The TV arm: standing rail + acting stage.
///
/// DPAD is explicit-target only (house rule: DPAD before paint, geometric
/// traversal forbidden). The rail is one vertical run — Quick Play, then the
/// channel rows (pinned group first), then the utility rows — LEFT anywhere
/// in the rail opens the app sidebar, RIGHT enters the stage at Tune in.
class _SpotlightTvArm extends StatefulWidget {
  final DebrifyTvView view;
  final double bottomInset;
  final FocusNode entryFocusNode;
  final bool isTelevision;

  const _SpotlightTvArm({
    required this.view,
    required this.bottomInset,
    required this.entryFocusNode,
    required this.isTelevision,
  });

  @override
  State<_SpotlightTvArm> createState() => _SpotlightTvArmState();
}

class _SpotlightTvArmState extends State<_SpotlightTvArm> {
  static const _kFind = 'find';
  static const _kAdd = 'add';
  static const _kImport = 'import';
  static const _kExport = 'export';
  static const _kDeleteAll = 'deleteAll';
  static const _kSettings = 'settings';
  static const _kSearch = 'search';

  /// The utility icon row under Quick Play, left to right.
  static const List<String> _utilRun = [
    _kFind,
    _kAdd,
    _kImport,
    _kExport,
    _kDeleteAll,
    _kSettings,
  ];
  static const _kPlay = 'act:play';
  static const _kPin = 'act:pin';
  static const _kEdit = 'act:edit';
  static const _kShare = 'act:share';
  static const _kDelete = 'act:del';

  // Health pip colours — status literals, same trio the mock draws.
  static const _kPipOk = Color(0xFF39D98A);
  static const _kPipWarn = Color(0xFFF4B860);
  static const _kPipBad = Color(0xFFFF6673);

  /// Nodes keyed by stable id (`ch:<id>` for channel rows). Created lazily,
  /// disposed once in [dispose] — a removed channel's node just idles.
  final Map<String, FocusNode> _nodes = {};
  final ScrollController _railScroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  /// Whether the search field is unfolded under the utility row. Closing it
  /// always clears the query — a hidden filter must never keep thinning the
  /// rail.
  bool _searchOpen = false;

  /// The utility icon the vertical run returns to — DOWN from Quick Play and
  /// UP from the list land on the icon the user last stood on.
  String _utilMemory = _kFind;

  /// The channel the stage is showing. Independent of DPAD focus: focus can
  /// sit on Quick Play while the stage keeps the last channel.
  String? _stagedId;

  /// The last channel id reported through [DebrifyTvView.onChannelFocused] —
  /// see [_notifyStagedIfChanged].
  String? _notifiedStagedId;

  @override
  void initState() {
    super.initState();
    // The stage draws a channel on frame one; phase 4's stats pass needs to
    // hear about it the same way it hears about every later focus move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyStagedIfChanged();
    });
  }

  @override
  void didUpdateWidget(_SpotlightTvArm old) {
    super.didUpdateWidget(old);
    final ids = {for (final c in widget.view.channels) c.id};
    final gone = [
      for (final k in _nodes.keys)
        if (k.startsWith('ch:') && !ids.contains(k.substring(3))) k,
    ];
    final stagedGone = _stagedId != null && !ids.contains(_stagedId);
    if (gone.isEmpty && !stagedGone) return;

    // Prune nodes for channels that no longer exist — an import/delete-heavy
    // session must not grow the map for the life of the mount. Disposal
    // waits a frame: the OLD subtree still holds these nodes until the
    // rebuild this didUpdateWidget precedes has landed.
    final removed = [for (final k in gone) _nodes.remove(k)!];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        for (final n in removed) {
          n.dispose();
        }
        return;
      }
      if (stagedGone) {
        // The staged channel was deleted. _staged already falls back to the
        // first remaining row visually; make it sticky and tell the state,
        // or the new channel's stage sits on its placeholder forever.
        final staged = _staged;
        setState(() => _stagedId = staged?.id);
        if (staged != null) {
          _notifiedStagedId = staged.id;
          widget.view.onChannelFocused(staged);
        }
      }
      // Explicit focus repair — never left to geometric traversal. Focus is
      // orphaned when the focused row/action unmounted with the deletion.
      final primary = FocusManager.instance.primaryFocus;
      final orphaned =
          primary == null ||
          primary is FocusScopeNode ||
          removed.contains(primary);
      if (orphaned) {
        final staged = _staged;
        if (staged != null) {
          _focusRail('ch:${staged.id}');
        } else {
          widget.entryFocusNode.requestFocus();
        }
      }
      for (final n in removed) {
        n.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _railScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  FocusNode _node(String key) => _nodes.putIfAbsent(
    key,
    () => FocusNode(debugLabel: 'debrify-tv-spotlight-$key'),
  );

  /// Channel rows in rail display order: pinned first, then the rest,
  /// thinned by the search query while the search field is open.
  List<DebrifyTvChannel> get _ordered {
    final fav = widget.view.favoriteIds;
    final all = [
      ...widget.view.channels.where((c) => fav.contains(c.id)),
      ...widget.view.channels.where((c) => !fav.contains(c.id)),
    ];
    final query = _query;
    if (query.isEmpty) return all;
    return [
      for (final c in all)
        if (_matches(c, query)) c,
    ];
  }

  String get _query => _searchOpen ? _search.text.trim().toLowerCase() : '';

  /// Same matcher as the touch arm: name, any keyword, or the channel number
  /// (bare or zero-padded, exact).
  static bool _matches(DebrifyTvChannel c, String query) {
    final number = c.channelNumber.toString();
    return c.name.toLowerCase().contains(query) ||
        c.keywords.any((k) => k.toLowerCase().contains(query)) ||
        number == query ||
        number.padLeft(2, '0') == query;
  }

  DebrifyTvChannel? get _staged {
    final ordered = _ordered;
    if (ordered.isEmpty) return null;
    for (final c in ordered) {
      if (c.id == _stagedId) return c;
    }
    return ordered.first;
  }

  void _stage(DebrifyTvChannel channel) {
    if (_stagedId == channel.id) return;
    setState(() => _stagedId = channel.id);
    _notifiedStagedId = channel.id;
    widget.view.onChannelFocused(channel);
  }

  /// The rail's VERTICAL focus run, top to bottom, as node keys. The whole
  /// utility icon row is one stop ('util'); LEFT/RIGHT move within it.
  List<String> get _railRun => [
    'qp',
    'util',
    if (_searchOpen) _kSearch,
    for (final c in _ordered) 'ch:${c.id}',
  ];

  FocusNode _railNode(String key) => key == 'qp'
      ? widget.entryFocusNode
      : key == 'util'
      ? _node(_utilMemory)
      : _node(key);

  void _focusRail(String key) {
    final node = _railNode(key);
    node.requestFocus();
    // Keep every focused channel row visible in the scroll region. Quick
    // Play, the utility row and the search field are pinned above it.
    final ctx = node.context;
    if (ctx != null && key.startsWith('ch:')) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 140),
      );
    }
  }

  KeyEventResult _railKey(String key, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final run = _railRun;
    final i = run.indexOf(key);

    if (k == LogicalKeyboardKey.arrowUp) {
      if (i > 0) _focusRail(run[i - 1]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (i >= 0 && i < run.length - 1) _focusRail(run[i + 1]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      // Sidebar opens ONLY via LEFT at column 0 (house policy).
      MainPageBridge.focusTvSidebar?.call();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (_staged != null) _node(_kPlay).requestFocus();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (isActivateKey(k) || k == LogicalKeyboardKey.space)) {
      _activateRail(key);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activateRail(String key) {
    final view = widget.view;
    switch (key) {
      case 'qp':
        if (!view.busy) view.onQuickPlay();
      default:
        final ch = _channelFor(key);
        // One press still plays: OK on a rail row tunes the channel.
        if (ch != null && !view.busy) view.onWatch(ch);
    }
  }

  /// Keys for the utility icon row: LEFT/RIGHT walk the icons, UP returns to
  /// Quick Play, DOWN drops into the search field / channel list, LEFT past
  /// the first icon opens the app sidebar (house policy: LEFT at column 0).
  KeyEventResult _utilKey(String key, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final i = _utilRun.indexOf(key);

    if (k == LogicalKeyboardKey.arrowLeft) {
      if (i > 0) {
        _node(_utilRun[i - 1]).requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (i < _utilRun.length - 1) {
        _node(_utilRun[i + 1]).requestFocus();
      } else if (_staged != null) {
        _node(_kPlay).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _focusRail('qp');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      final run = _railRun;
      final at = run.indexOf('util');
      if (at >= 0 && at < run.length - 1) _focusRail(run[at + 1]);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (isActivateKey(k) || k == LogicalKeyboardKey.space)) {
      _activateUtil(key);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activateUtil(String key) {
    final view = widget.view;
    switch (key) {
      case _kFind:
        _toggleSearch();
      case _kAdd:
        if (!view.busy) view.onAdd();
      case _kImport:
        if (!view.busy) view.onImport();
      case _kExport:
        if (!view.busy && view.channels.isNotEmpty) view.onExport();
      case _kSettings:
        view.onSettings();
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _search.clear();
    });
    if (_searchOpen) {
      // The field mounts on this frame's build; focus its shell right after.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchOpen) _node(_kSearch).requestFocus();
      });
    } else {
      _notifyStagedIfChanged();
      _node(_kFind).requestFocus();
    }
  }

  /// Every query change can swap the staged channel out from under the stage
  /// (the [_staged] fallback picks the first match). Tell the state when it
  /// does, or the stage keeps quiet placeholders until a row is focused.
  /// Compared against the last id actually reported — the controller's text
  /// has already changed by the time onChanged fires, so a before/after read
  /// around setState would always agree.
  void _notifyStagedIfChanged() {
    final staged = _staged;
    if (staged != null && staged.id != _notifiedStagedId) {
      _notifiedStagedId = staged.id;
      widget.view.onChannelFocused(staged);
    }
  }

  void _searchChanged() {
    setState(() {});
    _notifyStagedIfChanged();
  }

  /// The keyboard's Search key: an empty query folds the field away; a query
  /// with matches jumps to the first result.
  void _searchSubmitted(String text) {
    if (text.trim().isEmpty) {
      _toggleSearch();
      return;
    }
    final ordered = _ordered;
    if (ordered.isNotEmpty) _focusRail('ch:${ordered.first.id}');
  }

  DebrifyTvChannel? _channelFor(String key) {
    if (!key.startsWith('ch:')) return null;
    final id = key.substring(3);
    for (final c in widget.view.channels) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The pip resolves from rail-cheap signals ONLY (plan §7) — the expensive
  /// at-your-quality pass never runs for a rail row. Null while health has
  /// not loaded: no pip is drawn, never a placeholder that reads "healthy".
  Color? _pip(DebrifyTvChannel c) {
    final h = widget.view.railHealth[c.id];
    if (h == null) return null;
    if (h.status == DebrifyTvCacheStatus.failed || h.pooled == 0) {
      return _kPipBad;
    }
    if (h.pooled < kThinPoolThreshold || h.deadKeywords > 0) return _kPipWarn;
    return _kPipOk;
  }

  String _caption(DebrifyTvChannel c) {
    final h = widget.view.railHealth[c.id];
    final kws =
        '${c.keywords.length} '
        '${c.keywords.length == 1 ? 'keyword' : 'keywords'}';
    if (h == null) return kws;
    if (h.status == DebrifyTvCacheStatus.failed) {
      return 'Cache failed — rebuild';
    }
    return '${_thousands(h.pooled)} pooled · $kws';
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

  static const List<String> _actionRun = [
    _kPlay,
    _kPin,
    _kEdit,
    _kShare,
    _kDelete,
  ];

  /// The view's stats, ONLY when they were computed for the staged channel.
  /// Focus moves faster than the debounced pass; stats worn by the wrong
  /// channel are not a flicker — a plate press in that window would queue
  /// another channel's torrent.
  DebrifyTvChannelStats? get _stagedStats {
    final s = widget.view.stats;
    final staged = _staged;
    if (s == null || staged == null || s.channelId != staged.id) return null;
    return s;
  }

  int get _sampleCount => _stagedStats?.sample.length ?? 0;

  KeyEventResult _actionKey(String key, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final i = _actionRun.indexOf(key);

    if (k == LogicalKeyboardKey.arrowLeft) {
      if (i == 0) {
        // Back into the rail, at the staged channel's row.
        final staged = _staged;
        if (staged != null) _focusRail('ch:${staged.id}');
      } else {
        _node(_actionRun[i - 1]).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (i < _actionRun.length - 1) _node(_actionRun[i + 1]).requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      // Into the sample strip, at the plate over this action (mock §6).
      final n = _sampleCount;
      if (n > 0) _node('plate:${i < n ? i : n - 1}').requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (isActivateKey(k) || k == LogicalKeyboardKey.space)) {
      final staged = _staged;
      if (staged == null) return KeyEventResult.handled;
      final view = widget.view;
      switch (key) {
        case _kPlay:
          if (!view.busy) view.onWatch(staged);
        case _kPin:
          view.onToggleFavorite(staged);
        case _kEdit:
          view.onEdit(staged);
        case _kShare:
          view.onShare(staged);
        case _kDelete:
          view.onDelete(staged);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _plateKey(int index, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (index == 0) {
        final staged = _staged;
        if (staged != null) _focusRail('ch:${staged.id}');
      } else {
        _node('plate:${index - 1}').requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (index < _sampleCount - 1) {
        _node('plate:${index + 1}').requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _node(_kPlay).requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (isActivateKey(k) || k == LogicalKeyboardKey.space)) {
      _activatePlate(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activatePlate(int index) {
    final staged = _staged;
    final stats = _stagedStats;
    if (staged == null || stats == null || index >= stats.sample.length) {
      return;
    }
    if (!widget.view.busy) {
      widget.view.onWatchOne(staged, stats.sample[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final view = widget.view;
    final ordered = _ordered;
    final staged = _staged;
    final pinnedCount = ordered
        .where((c) => view.favoriteIds.contains(c.id))
        .length;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 22, 32, 16 + widget.bottomInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── The standing rail ─────────────────────────────────────
          Container(
            width: 286,
            padding: const EdgeInsets.only(right: 22),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: tv.hairline, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpotlightKick('Debrify TV', color: tv.accent),
                const SizedBox(height: 7),
                Text(
                  'Channels',
                  style: TextStyle(
                    fontSize: 31,
                    height: 0.98,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w800,
                    color: app.core.tx,
                  ),
                ),
                const SizedBox(height: 5),
                Builder(
                  builder: (context) {
                    if (_query.isNotEmpty) {
                      return Text(
                        '${ordered.length} of ${view.channels.length} '
                        'channels',
                        style: TextStyle(fontSize: 11.5, color: tv.textDim),
                      );
                    }
                    var pooled = 0;
                    for (final c in ordered) {
                      pooled += view.railHealth[c.id]?.pooled ?? 0;
                    }
                    final channels =
                        '${ordered.length} '
                        '${ordered.length == 1 ? 'channel' : 'channels'}';
                    return Text(
                      pooled > 0
                          ? '$channels · ${_thousands(pooled)} titles cached'
                          : channels,
                      style: TextStyle(fontSize: 11.5, color: tv.textDim),
                    );
                  },
                ),
                const SizedBox(height: 14),
                SpotlightRailButton(
                  focusNode: widget.entryFocusNode,
                  onKey: (n, e) => _railKey('qp', n, e),
                  onActivate: view.busy ? null : view.onQuickPlay,
                  icon: Icons.play_arrow_rounded,
                  label: 'Quick Play',
                  trailing: 'Any keyword',
                  primary: true,
                ),
                const SizedBox(height: 8),
                _utilityRow(context),
                if (_searchOpen) ...[
                  const SizedBox(height: 8),
                  _searchField(context),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _railScroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ordered.isEmpty && _query.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Text(
                              'No channels match '
                              '“${_search.text.trim()}”',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: tv.textFaint,
                              ),
                            ),
                          ),
                        if (pinnedCount > 0) ...[
                          SpotlightGroupLabel('Pinned', pinnedCount),
                          for (final c in ordered.take(pinnedCount))
                            _row(c, pinned: true, staged: staged),
                          SpotlightGroupLabel(
                            'Everything else',
                            ordered.length - pinnedCount,
                          ),
                        ],
                        for (final c in ordered.skip(pinnedCount))
                          _row(c, pinned: false, staged: staged),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          // ── The acting stage ──────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SpotlightStage(
                    channel: staged,
                    filtering: _query.isNotEmpty,
                    pinned:
                        staged != null && view.favoriteIds.contains(staged.id),
                    stats: _stagedStats,
                    busy: view.busy,
                    playNode: _node(_kPlay),
                    pinNode: _node(_kPin),
                    editNode: _node(_kEdit),
                    shareNode: _node(_kShare),
                    deleteNode: _node(_kDelete),
                    plateNodeFor: (i) => _node('plate:$i'),
                    onPlateKey: _plateKey,
                    onPlate: _activatePlate,
                    onKey: (n, e) {
                      for (final key in _actionRun) {
                        if (identical(_nodes[key], n)) {
                          return _actionKey(key, n, e);
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    onWatch: () {
                      if (staged != null) view.onWatch(staged);
                    },
                    onTogglePin: () {
                      if (staged != null) view.onToggleFavorite(staged);
                    },
                    onEdit: () {
                      if (staged != null) view.onEdit(staged);
                    },
                    onShare: () {
                      if (staged != null) view.onShare(staged);
                    },
                    onDelete: () {
                      if (staged != null) view.onDelete(staged);
                    },
                    onAdd: view.onAdd,
                    onImport: view.onImport,
                  ),
                ),
                if (widget.isTelevision) ...[
                  const SizedBox(height: 9),
                  _Legend(color: tv.textFaint),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The utility icon row pinned under Quick Play, plus a caption naming the
  /// focused icon (icon-only circles need one on a ten-foot UI).
  Widget _utilityRow(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final view = widget.view;

    Widget button(
      String key,
      IconData icon,
      String label,
      VoidCallback? onActivate, {
      bool active = false,
    }) {
      return SpotlightUtilityButton(
        focusNode: _node(key),
        onKey: (n, e) => _utilKey(key, n, e),
        onActivate: onActivate,
        onFocusChange: (focused) {
          if (focused) _utilMemory = key;
        },
        icon: icon,
        label: label,
        active: active,
      );
    }

    return Row(
      children: [
        button(
          _kFind,
          Icons.search_rounded,
          'Search',
          _toggleSearch,
          active: _searchOpen,
        ),
        const SizedBox(width: 7),
        button(
          _kAdd,
          Icons.add_rounded,
          'Add channel',
          view.busy ? null : view.onAdd,
        ),
        const SizedBox(width: 7),
        button(
          _kImport,
          Icons.cloud_download_rounded,
          'Import',
          view.busy ? null : view.onImport,
        ),
        const SizedBox(width: 7),
        button(
          _kExport,
          Icons.folder_zip_rounded,
          'Export',
          view.busy || view.channels.isEmpty ? null : view.onExport,
        ),
        const SizedBox(width: 7),
        button(
          _kDeleteAll,
          Icons.delete_sweep_rounded,
          'Delete all',
          view.busy || view.channels.isEmpty ? null : view.onDeleteAll,
        ),
        const SizedBox(width: 7),
        button(_kSettings, Icons.settings_rounded, 'Settings', view.onSettings),
        const SizedBox(width: 9),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([for (final k in _utilRun) _node(k)]),
            builder: (context, _) {
              const labels = {
                _kFind: 'Search',
                _kAdd: 'Add channel',
                _kImport: 'Import',
                _kExport: 'Export',
                _kDeleteAll: 'Delete all',
                _kSettings: 'Settings',
              };
              String caption = '';
              for (final k in _utilRun) {
                if (_node(k).hasFocus) {
                  caption = labels[k]!;
                  break;
                }
              }
              return Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: tv.textDim,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return TvTextField(
      controller: _search,
      focusNode: _node(_kSearch),
      style: TextStyle(fontSize: 12.5, color: app.core.tx),
      textInputAction: TextInputAction.search,
      // The shared TV shell/keyboard chrome follows settings.accent, same as
      // every other Debrify TV field (see magic_tv_screen's rationale).
      accent: app.settings.accent,
      keyboardGround: app.youtube.keyboardPanel,
      keyboardInk: app.core.tx,
      keyboardInkOnAccent: app.inkOn(app.settings.accent),
      decoration: InputDecoration(
        hintText: 'Search channels',
        hintStyle: TextStyle(fontSize: 12.5, color: tv.textFaint),
        prefixIcon: Icon(Icons.search_rounded, size: 16, color: tv.textFaint),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 34,
        ),
        isDense: true,
        filled: true,
        fillColor: tv.fillWeak,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: tv.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: tv.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: app.settings.accent, width: 1.5),
        ),
      ),
      onChanged: (_) => _searchChanged(),
      onSubmitted: _searchSubmitted,
      onUpArrow: () => _focusRail('util'),
      onDownArrow: () {
        final run = _railRun;
        final i = run.indexOf(_kSearch);
        if (i >= 0 && i < run.length - 1) _focusRail(run[i + 1]);
      },
      onLeftArrow: () => MainPageBridge.focusTvSidebar?.call(),
      onRightArrow: () {
        if (_staged != null) _node(_kPlay).requestFocus();
      },
    );
  }

  Widget _row(
    DebrifyTvChannel c, {
    required bool pinned,
    required DebrifyTvChannel? staged,
  }) {
    final key = 'ch:${c.id}';
    return SpotlightChannelRow(
      channel: c,
      pinned: pinned,
      staged: staged?.id == c.id,
      caption: _caption(c),
      pip: _pip(c),
      focusNode: _node(key),
      // Staging follows FOCUS, not activation: resting on a row redraws the
      // stage beside it.
      onFocusChange: (focused) {
        if (focused) _stage(c);
      },
      onKey: (n, e) => _railKey(key, n, e),
      onActivate: () {
        if (!widget.view.busy) widget.view.onWatch(c);
      },
      onLongPress: () => widget.view.onEdit(c),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  const _Legend({required this.color});

  @override
  Widget build(BuildContext context) {
    Widget item(String key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
    return Row(
      children: [
        item('OK', 'Tune this channel'),
        const SizedBox(width: 13),
        item('→', 'Channel actions'),
        const SizedBox(width: 13),
        item('←', 'App sidebar'),
      ],
    );
  }
}
