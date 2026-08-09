import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/iptv_media_store.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/dialog_tap_guard.dart';
import '../../utils/tv_keys.dart';
import '../tv_text_field.dart';

/// "Add to list" picker for one IPTV channel.
///
/// A multi-select checklist rather than the app's usual pick-one-and-pop
/// dialogs: a channel belongs to any number of lists at once, so every row
/// applies immediately and the dialog closes on Back/Done. That also matches
/// what the gesture used to do — hold-OK wrote the favourite the instant it
/// fired, and it would be a regression to make saving take a second confirm.
///
/// Returns true when anything actually changed, so the caller only reloads
/// then.
Future<bool> showIptvListPickerDialog({
  required BuildContext context,
  required String channelName,
  String? channelLogoUrl,
  required Future<List<IptvListMeta>> Function() loadLists,
  required Future<Set<String>> Function() loadMembership,
  required Future<void> Function(String listId, bool inList) onSetMembership,
  required Future<String> Function(String name) onCreateList,
}) async {
  // Tracked out here rather than through the route's result: rows apply
  // immediately, so a Back press or a tap on the barrier pops with null while
  // real writes have already happened. Reporting "nothing changed" then would
  // leave the caller's markers and shelf stale.
  final outcome = _PickerOutcome();
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _IptvListPickerDialog(
      outcome: outcome,
      channelName: channelName,
      channelLogoUrl: channelLogoUrl,
      loadLists: loadLists,
      loadMembership: loadMembership,
      onSetMembership: onSetMembership,
      onCreateList: onCreateList,
    ),
  );
  // Let the writes settle before the caller re-reads. Closing right after a
  // toggle would otherwise reload membership mid-transaction and paint the
  // pre-toggle state back over the change. Covers every close path, since
  // the barrier and Back never run the dialog's own close handler.
  await outcome.pending;
  return outcome.changed;
}

/// Survives the dialog's route so a dismissal can't lose what was written.
class _PickerOutcome {
  bool changed = false;
  Future<void> pending = Future<void>.value();

  /// Queue a mutation, keeping them ordered — two fast toggles of the same
  /// list must not race each other into the store.
  ///
  /// A failure is absorbed rather than propagated: the queue has to stay
  /// usable for the toggles behind it, and the caller awaits this only to
  /// know the writes have settled, not whether each one won.
  void run(Future<void> Function() mutation) {
    changed = true;
    pending = pending.then((_) => mutation()).catchError((Object error) {
      debugPrint('IptvListPicker: membership write failed: $error');
    });
  }
}

class _IptvListPickerDialog extends StatefulWidget {
  final _PickerOutcome outcome;
  final String channelName;
  final String? channelLogoUrl;
  final Future<List<IptvListMeta>> Function() loadLists;
  final Future<Set<String>> Function() loadMembership;
  final Future<void> Function(String listId, bool inList) onSetMembership;
  final Future<String> Function(String name) onCreateList;

  const _IptvListPickerDialog({
    required this.outcome,
    required this.channelName,
    required this.channelLogoUrl,
    required this.loadLists,
    required this.loadMembership,
    required this.onSetMembership,
    required this.onCreateList,
  });

  @override
  State<_IptvListPickerDialog> createState() => _IptvListPickerDialogState();
}

class _IptvListPickerDialogState extends State<_IptvListPickerDialog> {
  static const _accent = Color(0xFF8B5CF6);

  List<IptvListMeta> _lists = const [];
  Set<String> _membership = {};
  bool _loading = true;
  bool _creating = false;
  String? _nameError;

  final List<FocusNode> _rowNodes = [];
  final FocusNode _createRowNode = FocusNode(debugLabel: 'iptv-list-create');
  final FocusNode _nameFieldNode = FocusNode(debugLabel: 'iptv-list-name');
  final FocusNode _confirmNode = FocusNode(debugLabel: 'iptv-list-confirm');
  final FocusNode _cancelNode = FocusNode(debugLabel: 'iptv-list-cancel');
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final node in _rowNodes) {
      node.dispose();
    }
    _createRowNode.dispose();
    _nameFieldNode.dispose();
    _confirmNode.dispose();
    _cancelNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lists = await widget.loadLists();
    final membership = await widget.loadMembership();
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _membership = membership;
      _loading = false;
      _syncRowNodes();
    });
    // Land on the first row so DPAD starts somewhere sensible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _rowNodes.isNotEmpty) _rowNodes.first.requestFocus();
    });
  }

  void _syncRowNodes() {
    while (_rowNodes.length < _lists.length) {
      _rowNodes.add(FocusNode(debugLabel: 'iptv-list-row-${_rowNodes.length}'));
    }
    while (_rowNodes.length > _lists.length) {
      _rowNodes.removeLast().dispose();
    }
  }

  void _toggle(IptvListMeta list) {
    final nowIn = !_membership.contains(list.id);
    setState(() {
      if (nowIn) {
        _membership = {..._membership, list.id};
      } else {
        _membership = {..._membership}..remove(list.id);
      }
      // Keep the counts honest without a re-read — the row shows them.
      _lists = [
        for (final entry in _lists)
          if (entry.id != list.id)
            entry
          else
            IptvListMeta(
              id: entry.id,
              name: entry.name,
              position: entry.position,
              isBuiltin: entry.isBuiltin,
              channelCount: (entry.channelCount + (nowIn ? 1 : -1))
                  .clamp(0, 1 << 30),
            ),
      ];
    });
    // Queued rather than awaited here: the checkmark is already correct, and
    // the wrapper waits for the queue before the caller re-reads.
    widget.outcome.run(() => widget.onSetMembership(list.id, nowIn));
  }

  Future<void> _createAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Give the list a name');
      return;
    }
    final clash = _lists.any(
      (l) => l.name.toLowerCase() == name.toLowerCase(),
    );
    if (clash) {
      setState(() => _nameError = 'You already have a list called that');
      return;
    }

    // Queued like every other mutation so closing mid-create can't leave the
    // caller reading the store before the new list and its first channel
    // are actually in it.
    String? id;
    widget.outcome.run(() async {
      id = await widget.onCreateList(name);
      await widget.onSetMembership(id!, true);
    });
    await widget.outcome.pending;
    // Copied out because `id` is written inside a closure, which blocks
    // Dart's null promotion.
    final createdId = id;
    if (createdId == null) {
      if (mounted) setState(() => _nameError = 'Could not create that list');
      return;
    }
    if (!mounted) return;
    final lists = await widget.loadLists();
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _membership = {..._membership, createdId};
      _creating = false;
      _nameError = null;
      _nameController.clear();
      _syncRowNodes();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _lists.indexWhere((l) => l.id == createdId);
      if (index >= 0 && index < _rowNodes.length) {
        _rowNodes[index].requestFocus();
      }
    });
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final width = MediaQuery.of(context).size.width;
    return Dialog(
      backgroundColor: app.sheetSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width < 520 ? width : 460,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: _creating ? _buildCreateForm() : _buildList(),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final app = AppThemeScope.of(context);
    final logo = widget.channelLogoUrl;
    return Row(
      children: [
        if (logo != null && logo.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              logo,
              width: 34,
              height: 34,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(width: 34),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add to list',
                style: TextStyle(
                  color: app.core.tx,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: app.iptv.inkDim, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    final app = AppThemeScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _lists.length; i++)
                    _ListRow(
                      focusNode: _rowNodes[i],
                      label: _lists[i].name,
                      subtitle: _lists[i].channelCount == 1
                          ? '1 channel'
                          : '${_lists[i].channelCount} channels',
                      icon: _lists[i].isFavorites
                          ? Icons.favorite_rounded
                          : Icons.playlist_play_rounded,
                      iconColor: _lists[i].isFavorites
                          ? app.iptv.favoriteAccent
                          : app.iptv.inkMid,
                      checked: _membership.contains(_lists[i].id),
                      accent: _accent,
                      onTap: () => _toggle(_lists[i]),
                    ),
                  _ListRow(
                    focusNode: _createRowNode,
                    label: 'Create new list',
                    icon: Icons.add_rounded,
                    iconColor: _accent,
                    checked: false,
                    showCheckbox: false,
                    accent: _accent,
                    onTap: () {
                      setState(() {
                        _creating = true;
                        _nameError = null;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _nameFieldNode.requestFocus();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: _DialogButton(
            focusNode: _cancelNode,
            label: 'Done',
            accent: _accent,
            filled: true,
            onTap: _close,
          ),
        ),
      ],
    );
  }

  Widget _buildCreateForm() {
    final app = AppThemeScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 18),
        // Back on the (non-editing) field returns to the list instead of
        // bubbling on and popping the whole picker. While EDITING, TvTextField
        // consumes Back itself to close the keyboard, so this only sees the
        // shell-focused case.
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.goBack ||
                key == LogicalKeyboardKey.browserBack) {
              setState(() => _creating = false);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _createRowNode.requestFocus();
              });
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TvTextField(
            controller: _nameController,
            focusNode: _nameFieldNode,
            style: TextStyle(color: app.core.tx),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _confirmNode.requestFocus(),
            decoration: InputDecoration(
              labelText: 'List name',
              // 0x99 / 0x61 are Colors.white60 / white38 exactly — the
              // shorthands' alphas are 8-bit, so `withValues(0.6)` would be a
              // different value, not the same colour.
              labelStyle: TextStyle(color: app.core.tx.withAlpha(0x99)),
              hintText: 'e.g. Kids, Sports, Weekend',
              hintStyle: TextStyle(color: app.core.tx.withAlpha(0x61)),
              errorText: _nameError,
              filled: true,
              fillColor: app.iptv.fieldFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: app.iptv.fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: app.iptv.fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _accent, width: 2),
              ),
            ),
            onDownArrow: () => _confirmNode.requestFocus(),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _DialogButton(
              focusNode: _cancelNode,
              label: 'Cancel',
              accent: _accent,
              onTap: () {
                setState(() {
                  _creating = false;
                  _nameError = null;
                });
              },
            ),
            const SizedBox(width: 10),
            _DialogButton(
              focusNode: _confirmNode,
              label: 'Create & add',
              accent: _accent,
              filled: true,
              onTap: _createAndAdd,
            ),
          ],
        ),
      ],
    );
  }
}

/// One focusable checklist row. Focus is drawn with the accent ring the TV
/// pickers use so DPAD position is never ambiguous.
class _ListRow extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final bool checked;
  final bool showCheckbox;
  final Color accent;
  final VoidCallback onTap;

  const _ListRow({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.checked,
    required this.accent,
    required this.onTap,
    this.subtitle,
    this.showCheckbox = true,
  });

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          // DPAD Select also synthesizes a tap; mark it so the tap that
          // follows this key action doesn't fire the row a second time.
          DialogTapGuard.markKeyAction();
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (DialogTapGuard.shouldIgnoreTap()) return;
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accent.withValues(alpha: 0.18)
                : app.iptv.surfaceTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? widget.accent
                  : app.core.tx.withValues(alpha: 0.07),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 19, color: widget.iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          color: app.core.tx.withValues(alpha: 0.45),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.showCheckbox)
                Icon(
                  widget.checked
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 20,
                  color: widget.checked
                      ? widget.accent
                      : app.core.tx.withValues(alpha: 0.3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final Color accent;
  final bool filled;
  final VoidCallback onTap;

  const _DialogButton({
    required this.focusNode,
    required this.label,
    required this.accent,
    required this.onTap,
    this.filled = false,
  });

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          // DPAD Select also synthesizes a tap; mark it so the tap that
          // follows this key action doesn't fire the row a second time.
          DialogTapGuard.markKeyAction();
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (DialogTapGuard.shouldIgnoreTap()) return;
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: widget.filled
                ? widget.accent.withValues(alpha: _focused ? 1 : 0.85)
                : app.core.tx.withValues(alpha: _focused ? 0.16 : 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? app.core.tx.withValues(alpha: 0.9)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              // Filled = ink ON the accent swatch; ghost = page ink. Both are
              // white under legacy.
              color: widget.filled ? app.inkOn(widget.accent) : app.core.tx,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
