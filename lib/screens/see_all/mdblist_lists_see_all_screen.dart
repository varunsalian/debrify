import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/mdblist/mdblist_list_source.dart';
import '../../widgets/see_all/mdblist_list_card.dart';

/// Full-screen grid of the MDBList lists that matched a search — the "See All"
/// destination for the results-board lists rail. Purely presentational: it's
/// handed the already-fetched [lists] (no refetch, no paging — the rail holds
/// the complete `/lists/search` result set), and taps hand off to [onOpen].
///
/// This screen does NOT pop itself on tap: [onOpen] pushes the picked list's
/// items ON TOP of this grid, so Back retraces list items → grid → search
/// results, letting the user open one list, go Back, and open another.
class MdblistListsSeeAllScreen extends StatelessWidget {
  final String query;
  final List<MdblistListChoice> lists;
  final bool isTelevision;

  /// Open the picked list (search screen wires this to its Discover handoff).
  final void Function(MdblistListChoice list) onOpen;

  const MdblistListsSeeAllScreen({
    super.key,
    required this.query,
    required this.lists,
    required this.onOpen,
    this.isTelevision = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0910),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0910),
        elevation: 0,
        title: Text(
          query.isEmpty ? 'MDBList Lists' : 'Lists matching "$query"',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: lists.isEmpty
          ? Center(
              child: Text(
                'No lists to show.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                    // ~2:3 cards; columns scale with width (≈3 on a phone, more
                    // on tablets/desktop), matching the poster-rail card size.
                    maxCrossAxisExtent: 150,
                    childAspectRatio: 2 / 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
              itemCount: lists.length,
              itemBuilder: (context, index) {
                final list = lists[index];
                return _GridCell(
                  // Key by list id so a scrolled/recycled cell doesn't carry a
                  // stale debounce timestamp onto a different list.
                  key: ValueKey(list.id),
                  list: list,
                  // Autofocus the first cell on TV so the DPAD has a target.
                  autofocus: isTelevision && index == 0,
                  // Pushes the list's items on top of this grid (no pop here) —
                  // Back returns to the grid so another list can be opened.
                  onOpen: () => onOpen(list),
                );
              },
            ),
    );
  }
}

/// One grid cell: focus/hover state (TV DPAD + desktop mouse) drives the card's
/// highlight; Enter/Select or a tap opens the list.
class _GridCell extends StatefulWidget {
  final MdblistListChoice list;
  final bool autofocus;
  final VoidCallback onOpen;

  const _GridCell({
    super.key,
    required this.list,
    required this.autofocus,
    required this.onOpen,
  });

  @override
  State<_GridCell> createState() => _GridCellState();
}

class _GridCellState extends State<_GridCell> {
  bool _focused = false;
  bool _hovered = false;

  // [onOpen] pushes a route; debounce so one fast double-press doesn't push the
  // same list twice. A permanent guard would be wrong — the grid stays alive
  // and the user returns here to open other lists (and re-open the same one).
  DateTime? _lastActivate;

  void _activate() {
    final now = DateTime.now();
    if (_lastActivate != null &&
        now.difference(_lastActivate!) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastActivate = now;
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: MdblistListCard(
        list: widget.list,
        focused: _focused || _hovered,
        onTap: _activate,
      ),
    );
  }
}
