/// Implemented by the result-view states embedded in a [BrowseScreen]
/// (IPTV, YouTube) so the shared shell can move DPAD focus into their content
/// without knowing the concrete state type.
///
/// Kept in its own file to avoid a cycle between `browse_screen.dart` (which
/// calls it) and the result views (which implement it).
abstract interface class BrowseResultsFocusController {
  /// Focus the first interactive element in the results area (the entry point
  /// when a TV user moves focus down from the search field, or right/select
  /// from the sidebar). Mirrors the old `focusFirstFilter()` hooks.
  void focusFirstFilter();
}
