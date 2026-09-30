import 'package:flutter/widgets.dart';
import '../../search/models/search_mode.dart';

/// The screen controls outside the board that Home coordinates with: the
/// search field and mode, the Lists rail and Discover's source picker.
///
/// Home declares only what it uses; the screen composition implements it over
/// the Search and Discover sections, so Home never depends on them.
abstract interface class HomeScreenControls {
  SearchMode get mode;

  /// Assigns the mode without [switchMode]'s search side effects.
  set mode(SearchMode mode);
  void switchMode(SearchMode mode);

  /// Whether the search field or its adjacent controls hold focus.
  bool get searchFieldHasFocus;
  FocusNode get searchFieldNode;
  FocusNode get discoverSourceNode;
  List<FocusNode> get listsNodes;
  void clearListsSearch();
  Future<void> loadSourceTextFormatting({bool Function()? isCurrent});
}
