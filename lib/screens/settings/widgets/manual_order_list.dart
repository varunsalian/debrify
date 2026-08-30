import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import '../../../utils/tv_reveal.dart';
import '../../../widgets/tv_text_field.dart';
import 'settings_widgets.dart';

/// One reorderable row: identity plus what the row displays. The [id] is the
/// focus/selection identity and must be unique and stable across moves.
class ManualOrderItem {
  const ManualOrderItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.mutedIcon = false,
  });

  final Object id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool mutedIcon;
}

/// The shared manual-ordering surface: search, banner, and the list itself.
///
/// Interaction model is select-and-place, not carry: activating a row SELECTS
/// it, navigation then moves freely through the unchanged list (▲▼ one row,
/// ◀▶ jumps ten on DPAD), and activating a destination places the selection
/// there. The list never reshuffles while choosing a spot, so long moves cost
/// one navigation instead of one move per position. Short nudges keep their
/// old cost (select, step, place) and phone drag still works.
///
/// O(1) moves come from three places: the quick-move menu (hold OK on TV, the
/// ⋯ button elsewhere) with top/bottom/exact position, the search field —
/// typing filters, choosing a result jumps to it, or PLACES the selection on
/// it when one is active — and the ◀▶ page jumps.
class ManualOrderList extends StatefulWidget {
  const ManualOrderList({
    super.key,
    required this.items,
    required this.onMove,
    required this.enabled,
    required this.description,
    required this.emptyText,
    required this.focusLabelPrefix,
    this.onFocusAboveList,
    this.bannerTrailing,
    this.autofocusFirstRow = false,
  });

  final List<ManualOrderItem> items;

  /// Mutates the parent-owned list; the item at [from] must end at index [to]
  /// (List.removeAt + insert semantics).
  final void Function(int from, int to) onMove;

  final bool enabled;

  /// Leading sentence for the idle banner ('' for none); the widget appends
  /// the per-input how-to and replaces the whole banner while placing.
  final String description;
  final String emptyText;

  /// Row focus nodes are labeled `<prefix><hash>` — tests key off this.
  final String focusLabelPrefix;

  /// Where UP from the top of the list (or from the search field) lands.
  final VoidCallback? onFocusAboveList;

  /// Sits to the right of the banner (e.g. a reset button).
  final Widget? bannerTrailing;

  /// TV: focus the first row after the first frame.
  final bool autofocusFirstRow;

  /// Search earns its keystrokes only when scanning the list stops being
  /// instant; below this the field is noise.
  static const int searchThreshold = 6;

  @override
  State<ManualOrderList> createState() => ManualOrderListState();
}

class ManualOrderListState extends State<ManualOrderList> {
  final Map<Object, FocusNode> _nodes = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchNode = FocusNode(debugLabel: 'manual-order-search');
  final GlobalKey<TvTextFieldState> _searchFieldKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  late final TvHoldOk _hold = TvHoldOk(
    onTap: () => _activate(_holdIndex),
    onHold: () => _quickMoveMenu(_holdIndex),
  );

  Object? _pickedId;
  String _query = '';
  int _holdIndex = 0;

  bool get _searchable => widget.items.length >= ManualOrderList.searchThreshold;
  bool get _filtering => _query.trim().isNotEmpty;
  int get _pickedIndex => _pickedId == null
      ? -1
      : widget.items.indexWhere((item) => item.id == _pickedId);

  @override
  void initState() {
    super.initState();
    if (widget.autofocusFirstRow && widget.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.items.isNotEmpty) {
          _nodeFor(widget.items.first.id).requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ManualOrderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A selection can be orphaned from outside: a reset replaces the items, a
    // save disables the surface. Never leave a "Moving" badge pointing at
    // nothing.
    if (_pickedId != null &&
        (!widget.enabled || _pickedIndex < 0)) {
      _pickedId = null;
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _searchNode.dispose();
    _searchController.dispose();
    _scroll.dispose();
    _hold.reset();
    super.dispose();
  }

  /// True when a selection was active and is now cancelled — BACK peels the
  /// selection before closing the page.
  bool cancelPick() {
    if (_pickedId == null) return false;
    setState(() => _pickedId = null);
    return true;
  }

  /// The parent PopScope's vetoed-pop handler: true when the press was
  /// consumed here — by the search field's in-app keyboard (whose own
  /// PopScope vetoed the pop, but a veto is broadcast to every scope on the
  /// route) or by cancelling the active selection.
  bool handleBack() {
    if (_searchFieldKey.currentState?.popConsumedByShell == true) return true;
    return cancelPick();
  }

  FocusNode _nodeFor(Object id) => _nodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: '${widget.focusLabelPrefix}${id.hashCode}'),
  );

  /// Focuses row [index], scrolling it into existence first when the builder
  /// hasn't materialized it. Rows are uniform, so a proportional estimate
  /// lands within a viewport of the target and the post-frame retry snaps it.
  void _focusIndex(int index, {int attempts = 5}) {
    final items = widget.items;
    if (items.isEmpty) return;
    final clamped = index.clamp(0, items.length - 1);
    final node = _nodeFor(items[clamped].id);
    // FocusNode.context is never nulled on detach — a lazily built row that
    // scrolled out of the cache leaves a stale, unmounted context behind.
    final rowContext = node.context;
    if (rowContext != null && rowContext.mounted) {
      node.requestFocus();
      tvRevealMinimal(rowContext);
      return;
    }
    if (attempts <= 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    final total = position.maxScrollExtent + position.viewportDimension;
    final extent = total / items.length;
    final target = (clamped * extent - position.viewportDimension / 2).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusIndex(clamped, attempts: attempts - 1);
    });
  }

  /// A row was activated (OK/Enter/tap): select it, cancel by re-activating,
  /// or place the active selection at its position.
  void _activate(int index) {
    if (!widget.enabled) return;
    final items = widget.items;
    if (index < 0 || index >= items.length) return;
    final id = items[index].id;
    final pickedIndex = _pickedIndex;
    if (pickedIndex < 0) {
      setState(() => _pickedId = id);
      return;
    }
    if (items[pickedIndex].id == id) {
      setState(() => _pickedId = null);
      return;
    }
    _place(pickedIndex, index);
  }

  void _place(int from, int to) {
    final id = widget.items[from].id;
    widget.onMove(from, to);
    setState(() => _pickedId = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.items.indexWhere((item) => item.id == id);
      if (index >= 0) _focusIndex(index);
    });
  }

  void _moveTo(int from, int to) {
    if (!widget.enabled || from == to) return;
    _place(from, to.clamp(0, widget.items.length - 1));
  }

  KeyEventResult _onRowKey(int index, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      // TvHoldOk needs the OK key-up to tell a tap from a hold.
      if (event is KeyUpEvent &&
          PlatformUtil.isTelevision &&
          isActivateOrSpaceKey(event.logicalKey)) {
        return _hold.handle(event);
      }
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isActivateOrSpaceKey(key)) {
      if (PlatformUtil.isTelevision) {
        _holdIndex = index;
        return _hold.handle(event);
      }
      if (event is KeyDownEvent) _activate(index);
      return KeyEventResult.handled;
    }
    final picked = _pickedIndex >= 0;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final target = key == LogicalKeyboardKey.arrowUp ? index - 1 : index + 1;
      if (target < 0) {
        // The search field is part of the placing flow (find the destination,
        // place on the result), so UP reaches it even mid-move. The header
        // buttons are not: while placing, that edge is a wall — an accidental
        // OK on Done would save mid-move; BACK is the way out.
        if (_searchable) {
          _searchNode.requestFocus();
        } else if (!picked) {
          widget.onFocusAboveList?.call();
        }
        return KeyEventResult.handled;
      }
      if (target >= widget.items.length) return KeyEventResult.handled;
      _focusIndex(target);
      return KeyEventResult.handled;
    }
    if (picked &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _focusIndex(key == LogicalKeyboardKey.arrowLeft ? index - 10 : index + 10);
      return KeyEventResult.handled;
    }
    if (picked &&
        event is KeyDownEvent &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack)) {
      setState(() => _pickedId = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Quick moves ──────────────────────────────────────────────────────────

  Future<void> _quickMoveMenu(int index) async {
    if (!widget.enabled) return;
    final items = widget.items;
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    final t = AppThemeScope.of(context).settings;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.panel,
      builder: (sheetContext) => TvHeldKeyGuard(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.vertical_align_top_rounded),
                title: const Text('Move to top'),
                onTap: () => Navigator.of(sheetContext).pop('top'),
              ),
              ListTile(
                leading: const Icon(Icons.vertical_align_bottom_rounded),
                title: const Text('Move to bottom'),
                onTap: () => Navigator.of(sheetContext).pop('bottom'),
              ),
              if (!PlatformUtil.isTelevision)
                ListTile(
                  leading: const Icon(Icons.pin_rounded),
                  title: const Text('Move to position…'),
                  onTap: () => Navigator.of(sheetContext).pop('position'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'top':
        _moveTo(index, 0);
      case 'bottom':
        _moveTo(index, widget.items.length - 1);
      case 'position':
        await _promptPosition(index);
    }
  }

  Future<void> _promptPosition(int index) async {
    final length = widget.items.length;
    final controller = TextEditingController(text: '${index + 1}');
    final position = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to position'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: '1–$length'),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(int.tryParse(controller.text)),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    // The dialog's exit transition still paints the TextField for a few
    // frames after showDialog resolves; dispose once it is fully gone.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose),
    );
    if (!mounted || position == null) return;
    _moveTo(index, position.clamp(1, length) - 1);
  }

  // ── Search ───────────────────────────────────────────────────────────────

  List<int> _filteredIndexes() {
    final query = _query.trim().toLowerCase();
    return [
      for (var i = 0; i < widget.items.length; i++)
        if (widget.items[i].title.toLowerCase().contains(query)) i,
    ];
  }

  /// Choosing a result jumps to that row — or, with a selection active,
  /// places the selection on it. Either way search has done its job: clear it
  /// and land focus on the row in the full list.
  void _activateSearchResult(int originalIndex) {
    if (!widget.enabled) return;
    final pickedIndex = _pickedIndex;
    final targetId = widget.items[originalIndex].id;
    _searchController.clear();
    setState(() => _query = '');
    if (pickedIndex >= 0 && widget.items[pickedIndex].id != targetId) {
      widget.onMove(pickedIndex, originalIndex);
      setState(() => _pickedId = null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.items.indexWhere((item) => item.id == targetId);
      if (index >= 0) _focusIndex(index);
    });
  }

  void _focusFirstResult() {
    final matches = _filtering ? _filteredIndexes() : null;
    if (matches != null) {
      if (matches.isNotEmpty) _focusIndex(matches.first);
    } else if (widget.items.isNotEmpty) {
      _focusIndex(0);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  String _bannerText() {
    final pickedIndex = _pickedIndex;
    if (pickedIndex >= 0) {
      final title = widget.items[pickedIndex].title;
      if (PlatformUtil.isTelevision) {
        return 'Moving "$title" — highlight where it goes with ▲▼ (◀▶ jumps '
            '10), press OK to place it, BACK to cancel.';
      }
      if (PlatformUtil.isPhone) {
        return 'Moving "$title" — tap where it goes.';
      }
      return 'Moving "$title" — click or Enter where it goes, Esc cancels.';
    }
    final lead = widget.description.isEmpty ? '' : '${widget.description} ';
    if (widget.items.length < 2) {
      return '${lead}At least two rows are needed to change the order.';
    }
    if (PlatformUtil.isTelevision) {
      return '${lead}Press OK to pick a row, highlight where it goes, then '
          'press OK to place it. Hold OK for quick moves.';
    }
    if (PlatformUtil.isPhone) {
      return '${lead}Drag a row, or tap it and tap where it goes. '
          'The ⋯ button has quick moves.';
    }
    return '${lead}Drag a row, or click it and click where it goes. '
        'The ⋯ button has quick moves.';
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final pickedIndex = _pickedIndex;
    return Column(
      children: [
        if (_searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TvTextField(
              key: _searchFieldKey,
              controller: _searchController,
              focusNode: _searchNode,
              hintText: 'Search…',
              textInputAction: TextInputAction.search,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : ExcludeFocus(
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Clear',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ),
              enabled: widget.enabled,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) => _focusFirstResult(),
              onDownArrow: _focusFirstResult,
              onUpArrow: widget.onFocusAboveList,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(child: SettingsInfoBanner(text: _bannerText())),
              if (widget.bannerTrailing != null) ...[
                const SizedBox(width: 12),
                widget.bannerTrailing!,
              ],
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(widget.emptyText))
              : _filtering
              ? _buildSearchResults(pickedIndex)
              : _buildFullList(items, pickedIndex),
        ),
      ],
    );
  }

  Widget _buildFullList(List<ManualOrderItem> items, int pickedIndex) {
    return ReorderableListView.builder(
      scrollController: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderItem: widget.enabled ? widget.onMove : (_, _) {},
      itemBuilder: (context, index) => ManualOrderRow(
        key: ValueKey(items[index].id),
        item: items[index],
        index: index,
        node: _nodeFor(items[index].id),
        enabled: widget.enabled,
        picked: index == pickedIndex,
        pickedIndex: pickedIndex < 0 ? null : pickedIndex,
        onKey: (event) => _onRowKey(index, event),
        // A key rollover can carry focus away mid-press (OK held, then UP on
        // the top row); without this the dwell timer survives and pops the
        // quick-move menu over whatever now has focus.
        onFocusLost: _hold.reset,
        onTap: () => _activate(index),
        onMoveUp: widget.enabled && index > 0
            ? () => _moveTo(index, index - 1)
            : null,
        onMoveDown: widget.enabled && index < items.length - 1
            ? () => _moveTo(index, index + 1)
            : null,
        onQuickMoves: widget.enabled ? () => _quickMoveMenu(index) : null,
      ),
    );
  }

  /// The filtered view finds rows; it never reorders them — positions inside
  /// a filtered list are meaningless. Rows keep their full-list numbers and
  /// activation jumps (or places) in the full list.
  Widget _buildSearchResults(int pickedIndex) {
    final matches = _filteredIndexes();
    if (matches.isEmpty) {
      return const Center(child: Text('No matches.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
      itemCount: matches.length,
      itemBuilder: (context, position) {
        final index = matches[position];
        final item = widget.items[index];
        return ManualOrderRow(
          key: ValueKey(item.id),
          item: item,
          index: index,
          node: _nodeFor(item.id),
          enabled: widget.enabled,
          picked: index == pickedIndex,
          pickedIndex: null,
          searchResult: true,
          placeTarget: pickedIndex >= 0 && index != pickedIndex,
          onKey: (event) => _onSearchRowKey(position, matches, event),
          onTap: () => _activateSearchResult(index),
          onMoveUp: null,
          onMoveDown: null,
          onQuickMoves: null,
        );
      },
    );
  }

  KeyEventResult _onSearchRowKey(
    int position,
    List<int> matches,
    KeyEvent event,
  ) {
    if (!widget.enabled) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
      _activateSearchResult(matches[position]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final target = key == LogicalKeyboardKey.arrowUp
          ? position - 1
          : position + 1;
      if (target < 0) {
        _searchNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (target >= matches.length) return KeyEventResult.handled;
      final node = _nodeFor(widget.items[matches[target]].id);
      node.requestFocus();
      final rowContext = node.context;
      if (rowContext != null && rowContext.mounted) tvRevealMinimal(rowContext);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        _pickedIndex >= 0 &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack)) {
      setState(() => _pickedId = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class ManualOrderRow extends StatefulWidget {
  const ManualOrderRow({
    super.key,
    required this.item,
    required this.index,
    required this.node,
    required this.enabled,
    required this.picked,
    required this.pickedIndex,
    required this.onKey,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onQuickMoves,
    this.onFocusLost,
    this.searchResult = false,
    this.placeTarget = false,
  });

  final ManualOrderItem item;
  final int index;
  final FocusNode node;
  final bool enabled;
  final bool picked;

  /// Index of the row being moved, when one is — the focused row draws its
  /// insertion marker on the edge the selection would land on.
  final int? pickedIndex;
  final KeyEventResult Function(KeyEvent) onKey;
  final VoidCallback onTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onQuickMoves;

  /// Fired when the row loses focus — the list resets its hold-OK recognizer
  /// so an in-flight press cannot fire against a row that is no longer under
  /// the cursor.
  final VoidCallback? onFocusLost;
  final bool searchResult;
  final bool placeTarget;

  @override
  State<ManualOrderRow> createState() => _ManualOrderRowState();
}

class _ManualOrderRowState extends State<ManualOrderRow> {
  bool get _focused => widget.node.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final active = widget.picked || _focused;
    final item = widget.item;
    final pickedIndex = widget.pickedIndex;
    final dropTarget =
        _focused && pickedIndex != null && pickedIndex != widget.index;
    final dropBelow = dropTarget && widget.index > pickedIndex;
    final marker = Container(
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return Focus(
      focusNode: widget.node,
      onFocusChange: (focused) {
        if (focused && PlatformUtil.isTelevision) tvRevealMinimal(context);
        if (!focused) widget.onFocusLost?.call();
        setState(() {});
      },
      onKeyEvent: (_, event) => widget.onKey(event),
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.enabled ? widget.onTap : null,
        borderRadius: app.shape.br(12),
        child: Column(
          children: [
            if (dropTarget && !dropBelow) marker,
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: EdgeInsets.only(
                top: dropTarget && !dropBelow ? 3 : 0,
                bottom: dropTarget && dropBelow ? 3 : 6,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: active ? t.panel2 : t.panel,
                borderRadius: app.shape.br(12),
                border: Border.all(color: active ? t.accent : t.line),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${widget.index + 1}',
                      style: TextStyle(
                        color: active ? t.accent2 : t.dim,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    item.icon,
                    size: 22,
                    color: item.mutedIcon ? t.dim2 : t.dim,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (item.subtitle.isNotEmpty)
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.dim, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (widget.picked)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Moving…',
                        style: TextStyle(
                          color: t.accent2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if ((dropTarget || widget.placeTarget) && !widget.picked)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Place here',
                        style: TextStyle(
                          color: t.accent2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (!PlatformUtil.isTelevision && !widget.searchResult)
                    ExcludeFocus(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // A 320dp phone row has no width for three buttons
                          // plus the drag handle; there, drag and tap-to-place
                          // cover the arrows' job and ⋯ keeps the quick moves.
                          if (!PlatformUtil.isPhone) ...[
                            IconButton(
                              tooltip: 'Move up',
                              onPressed: widget.onMoveUp,
                              icon: const Icon(Icons.keyboard_arrow_up_rounded),
                            ),
                            IconButton(
                              tooltip: 'Move down',
                              onPressed: widget.onMoveDown,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                            ),
                          ],
                          IconButton(
                            tooltip: 'Quick moves',
                            onPressed: widget.onQuickMoves,
                            icon: const Icon(Icons.more_vert_rounded),
                          ),
                        ],
                      ),
                    ),
                  if (!PlatformUtil.isTelevision &&
                      !widget.searchResult &&
                      widget.enabled)
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Icon(Icons.drag_indicator_rounded, color: t.dim),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (dropTarget && dropBelow) marker,
          ],
        ),
      ),
    );
  }
}
