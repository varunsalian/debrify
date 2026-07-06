import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/main_page_bridge.dart';
import '../widgets/browse/browse_results_focus.dart';
import '../widgets/browse/browse_search_header.dart';

/// Arguments handed to a [BrowseScreen.viewBuilder] to construct its result
/// view. The builder must attach [resultKey] to the view (its state must
/// implement [BrowseResultsFocusController]) and forward [query],
/// [isTelevision], and [onUpArrowToSearch].
///
/// [searchToken] increments on every submit — including a re-submit of the
/// same text — so submit-mode views can force a fresh search off it instead of
/// dedup'ing on an unchanged query string.
class BrowseViewArgs {
  final GlobalKey resultKey;
  final String query;
  final int searchToken;
  final bool isTelevision;
  final VoidCallback onUpArrowToSearch;

  const BrowseViewArgs({
    required this.resultKey,
    required this.query,
    required this.searchToken,
    required this.isTelevision,
    required this.onUpArrowToSearch,
  });
}

/// Shared full-screen shell for the "Browse" sidebar tabs (IPTV, YouTube).
///
/// Owns the search field + query state and the TV DPAD plumbing (content-focus
/// handler registration, down-arrow-into-content, up-arrow-back-to-search) so
/// each source only has to supply a hint and a result view. [isTelevision] is
/// passed in from the app shell (already resolved) rather than re-detected, so
/// the first frame renders in the correct layout with no flash.
class BrowseScreen extends StatefulWidget {
  /// Nav tab index, used to register the TV content-focus handler.
  final int tabIndex;
  final String hintText;

  /// When true (YouTube), the query is committed on submit and a network search
  /// runs. When false (IPTV), the query updates live for local filtering.
  final bool submitOnly;
  final bool isTelevision;
  final Widget Function(BrowseViewArgs args) viewBuilder;

  const BrowseScreen({
    super.key,
    required this.tabIndex,
    required this.hintText,
    required this.submitOnly,
    required this.isTelevision,
    required this.viewBuilder,
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'browse-search');
  final GlobalKey _resultKey = GlobalKey();

  String _query = '';
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    // Assigning the node's own handler (rather than an ancestor Focus) so it
    // runs before the default text-editing shortcuts, which would otherwise
    // swallow the arrow key on a single-line field.
    _searchFocusNode.onKeyEvent = _handleSearchKey;
    MainPageBridge.registerTvContentFocusHandler(
      widget.tabIndex,
      _focusContent,
    );
  }

  /// Down-arrow from the search field drops focus into the results/filters
  /// (DPAD on TV, arrow key on desktop); everything else — typing, cursor
  /// keys — passes through untouched.
  KeyEventResult _handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _focusContent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(
      widget.tabIndex,
      _focusContent,
    );
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// TV DPAD entry point: move focus from the sidebar into the result content.
  void _focusContent() {
    final Object? state = _resultKey.currentState;
    if (state is BrowseResultsFocusController) {
      state.focusFirstFilter();
    }
  }

  void _onChanged(String value) {
    // Live filtering (IPTV): reflect every keystroke in the query.
    setState(() => _query = value);
  }

  void _onSubmitted(String value) {
    // Submit mode (YouTube): commit the query and bump the token so an
    // identical re-submit (e.g. retry after a network error) still re-runs.
    setState(() {
      _query = value.trim();
      _searchToken++;
    });
  }

  void _onClear() {
    _searchController.clear();
    setState(() {
      _query = '';
      _searchToken++;
    });
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BrowseSearchHeader(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: widget.hintText,
              onChanged: widget.submitOnly ? null : _onChanged,
              onSubmitted: widget.submitOnly ? _onSubmitted : null,
              onClear: _onClear,
            ),
            Expanded(
              child: widget.viewBuilder(
                BrowseViewArgs(
                  resultKey: _resultKey,
                  query: _query,
                  searchToken: _searchToken,
                  isTelevision: widget.isTelevision,
                  onUpArrowToSearch: _searchFocusNode.requestFocus,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
