import 'package:flutter/material.dart';
import '../../../models/mdblist_list_choice.dart';
import '../models/lists_search_state.dart';
import 'lists_search_rail.dart';

typedef ListsSearchRowsDeps = ({
  ListsSearchState Function() state,
  List<FocusNode> Function() nodes,
  bool Function() isTelevision,
  double Function(BuildContext) posterWidth,
  Widget Function(VoidCallback) header,
  Widget Function(IconData, String, String) message,
  ValueChanged<MdblistListChoice> open,
  VoidCallback openSeeAll,
  VoidCallback focusSidebar,
  VoidCallback onUp,
});

/// Lists result and rail rendering; request, focus and navigation owners are borrowed.
class ListsSearchRows {
  ListsSearchRows(this._deps);
  final ListsSearchRowsDeps _deps;
  Widget build(BuildContext context) => buildListsSearchContent(
    context,
    searching: _deps.state().searching,
    error: _deps.state().error,
    query: _deps.state().query,
    hasResults: _deps.state().results.isNotEmpty,
    message: (icon, title, body) => _deps.message(icon, title, body),
    rail: () => _buildListsRailRow(context),
  );

  /// The MDBList list-search result rail. Same 2:3 card
  /// footprint as the poster rows; each card is a gradient tile (list glyph +
  /// centred name + items/likes footer, no artwork). Select opens the list's
  /// items — pushed over the board on TV (Back returns here), or in the
  /// Discover tab on mobile/laptop. DPAD: up → search field, left off card 0 →
  /// sidebar (TV); the single result rail deliberately holds Down in place.
  Widget _buildListsRailRow(BuildContext context) => buildListsSearchRail(
    posterW: _deps.posterWidth(context),
    header: _deps.header(_deps.openSeeAll),
    results: () => _deps.state().results,
    nodes: _deps.nodes(),
    isTelevision: _deps.isTelevision(),
    onOpen: _deps.open,
    onSidebar: _deps.focusSidebar,
    onUp: _deps.onUp,
  );
}
