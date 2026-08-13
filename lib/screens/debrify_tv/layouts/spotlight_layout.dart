import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../services/main_page_bridge.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import 'debrify_tv_view.dart';
import 'spotlight_rail.dart';
import 'spotlight_stage.dart';

/// The Spotlight Debrify TV layout (`debrify_tv_style` = `spotlight`).
///
/// Resolves the device class INSIDE the style, like `detail_page_style` does:
/// television is tested before anything else — a 1920×1080 TV is 960×540
/// logical, and a width-only check would send it to a touch arm.
///
/// The mock at `design/mockups/debrify_tv_spotlight_mockup/` is the spec;
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
    // Television first. The phone/touch arm is a phase-5 deliverable; until
    // it lands every device class renders the TV arm — exactly what the grid
    // era did, so nothing regresses in the meantime.
    return _SpotlightTvArm(
      view: view,
      bottomInset: bottomInset,
      entryFocusNode: entryFocusNode,
      isTelevision: PlatformUtil.isTelevision,
    );
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
  static const _kAdd = 'add';
  static const _kImport = 'import';
  static const _kSettings = 'settings';
  static const _kPlay = 'act:play';
  static const _kPin = 'act:pin';
  static const _kEdit = 'act:edit';
  static const _kShare = 'act:share';
  static const _kDelete = 'act:del';

  /// Nodes keyed by stable id (`ch:<id>` for channel rows). Created lazily,
  /// disposed once in [dispose] — a removed channel's node just idles.
  final Map<String, FocusNode> _nodes = {};
  final ScrollController _railScroll = ScrollController();

  /// The channel the stage is showing. Independent of DPAD focus: focus can
  /// sit on Quick Play while the stage keeps the last channel.
  String? _stagedId;

  @override
  void initState() {
    super.initState();
    // The stage draws a channel on frame one; phase 4's stats pass needs to
    // hear about it the same way it hears about every later focus move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final staged = _staged;
      if (staged != null) widget.view.onChannelFocused(staged);
    });
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _railScroll.dispose();
    super.dispose();
  }

  FocusNode _node(String key) => _nodes.putIfAbsent(
    key,
    () => FocusNode(debugLabel: 'debrify-tv-spotlight-$key'),
  );

  /// Channel rows in rail display order: pinned first, then the rest.
  List<DebrifyTvChannel> get _ordered {
    final fav = widget.view.favoriteIds;
    return [
      ...widget.view.channels.where((c) => fav.contains(c.id)),
      ...widget.view.channels.where((c) => !fav.contains(c.id)),
    ];
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
    widget.view.onChannelFocused(channel);
  }

  /// The rail's focus run, top to bottom, as node keys.
  List<String> get _railRun => [
    'qp',
    for (final c in _ordered) 'ch:${c.id}',
    _kAdd,
    _kImport,
    _kSettings,
  ];

  FocusNode _railNode(String key) =>
      key == 'qp' ? widget.entryFocusNode : _node(key);

  void _focusRail(String key) {
    final node = _railNode(key);
    node.requestFocus();
    // Keep the focused row on screen; the rail list scrolls, the header and
    // Quick Play stand.
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
      case _kAdd:
        if (!view.busy) view.onAdd();
      case _kImport:
        if (!view.busy) view.onImport();
      case _kSettings:
        view.onSettings();
      default:
        final ch = _channelFor(key);
        // One press still plays: OK on a rail row tunes the channel.
        if (ch != null && !view.busy) view.onWatch(ch);
    }
  }

  DebrifyTvChannel? _channelFor(String key) {
    if (!key.startsWith('ch:')) return null;
    final id = key.substring(3);
    for (final c in widget.view.channels) {
      if (c.id == id) return c;
    }
    return null;
  }

  static const List<String> _actionRun = [
    _kPlay,
    _kPin,
    _kEdit,
    _kShare,
    _kDelete,
  ];

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
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      // The sample strip (phase 4) will take UP; DOWN has nothing below.
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

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final view = widget.view;
    final ordered = _ordered;
    final staged = _staged;
    final pinnedCount = ordered.where((c) => view.favoriteIds.contains(c.id)).length;

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
                Text(
                  '${ordered.length} '
                  '${ordered.length == 1 ? 'channel' : 'channels'}',
                  style: TextStyle(fontSize: 11.5, color: tv.textDim),
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
                Expanded(
                  child: SingleChildScrollView(
                    controller: _railScroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        const SizedBox(height: 10),
                        SpotlightRailButton(
                          focusNode: _node(_kAdd),
                          onKey: (n, e) => _railKey(_kAdd, n, e),
                          onActivate: view.busy ? null : view.onAdd,
                          icon: Icons.add_rounded,
                          label: 'Add channel',
                          compact: true,
                        ),
                        const SizedBox(height: 5),
                        SpotlightRailButton(
                          focusNode: _node(_kImport),
                          onKey: (n, e) => _railKey(_kImport, n, e),
                          onActivate: view.busy ? null : view.onImport,
                          icon: Icons.cloud_download_rounded,
                          label: 'Import',
                          compact: true,
                        ),
                        const SizedBox(height: 5),
                        SpotlightRailButton(
                          focusNode: _node(_kSettings),
                          onKey: (n, e) => _railKey(_kSettings, n, e),
                          onActivate: view.onSettings,
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          compact: true,
                        ),
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
                    pinned:
                        staged != null &&
                        view.favoriteIds.contains(staged.id),
                    busy: view.busy,
                    playNode: _node(_kPlay),
                    pinNode: _node(_kPin),
                    editNode: _node(_kEdit),
                    shareNode: _node(_kShare),
                    deleteNode: _node(_kDelete),
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
      caption:
          '${c.keywords.length} '
          '${c.keywords.length == 1 ? 'keyword' : 'keywords'}',
      pip: null, // phase 4: rail health
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
