import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/search_mode.dart';

/// Owns the shared query/mode focus resources. Result and board nodes are
/// borrowed from their views; current targets are supplied at interaction time.
class SearchFocusController {
  SearchFocusController({required this.onSourcesVisibilityChanged});

  final VoidCallback onSourcesVisibilityChanged;
  final field = FocusNode(debugLabel: 'search_field');
  final catalog = FocusNode(debugLabel: 'mode_catalog');
  final keyword = FocusNode(debugLabel: 'mode_keyword');
  final lists = FocusNode(debugLabel: 'mode_lists');
  final dropdown = FocusNode(debugLabel: 'mode_dropdown');
  Timer? _hideSources;
  bool _sourcesVisible = false;
  bool _disposed = false;

  bool get sourcesVisible => _sourcesVisible;
  bool get hasFocus =>
      field.hasFocus ||
      catalog.hasFocus ||
      keyword.hasFocus ||
      lists.hasFocus ||
      dropdown.hasFocus;

  static bool useCompactModeMenu({
    required bool listsEnabled,
    required bool isTelevision,
    required double width,
  }) => listsEnabled && width < (isTelevision ? 900 : 342);

  void focusMode(SearchMode mode, {required bool compact}) {
    if (_disposed) return;
    (compact
            ? dropdown
            : switch (mode) {
                SearchMode.catalog => catalog,
                SearchMode.keyword => keyword,
                SearchMode.lists => lists,
              })
        .requestFocus();
  }

  void focusFieldAtEnd(TextEditingController text) {
    if (_disposed) return;
    field.requestFocus();
    text.selection = TextSelection.collapsed(offset: text.text.length);
  }

  /// Discovery enters its leading filter. Search enters mounted results, or
  /// the field. Home uses its layout's top target; an empty TV board returns
  /// to the sidebar only after loading, preserving arrival autofocus.
  void focusContent({
    required bool discoverMode,
    required bool searchMode,
    required bool isTelevision,
    required SearchMode mode,
    required FocusNode discoverSource,
    required FocusNode? keywordToolbar,
    required FocusNode? listsResult,
    required FocusNode? catalogResult,
    required VoidCallback? focusCatalogShelf,
    required FocusNode? Function() topBoardNode,
    required bool loading,
    required VoidCallback focusSidebar,
  }) {
    if (_disposed) return;
    if (discoverMode) {
      discoverSource.requestFocus();
      return;
    }
    if (mode == SearchMode.keyword) {
      (keywordToolbar ?? field).requestFocus();
      return;
    }
    if (mode == SearchMode.lists) {
      (listsResult ?? field).requestFocus();
      return;
    }
    if (searchMode) {
      if (catalogResult != null && focusCatalogShelf != null) {
        focusCatalogShelf();
      } else {
        (catalogResult ?? field).requestFocus();
      }
      return;
    }
    final top = topBoardNode();
    if (top != null) {
      top.requestFocus();
    } else if (!isTelevision) {
      field.requestFocus();
    } else if (!loading) {
      focusSidebar();
    }
  }

  /// Keep Sources mounted through a click that blurs the field. Refocusing
  /// within the 250ms window cancels the hide, including during a pending tap.
  void onFieldFocusForSources() {
    if (_disposed) return;
    _hideSources?.cancel();
    if (field.hasFocus) {
      _setSourcesVisible(true);
    } else {
      _hideSources = Timer(const Duration(milliseconds: 250), () {
        if (!_disposed) _setSourcesVisible(false);
      });
    }
  }

  void _setSourcesVisible(bool visible) {
    if (_sourcesVisible == visible) return;
    _sourcesVisible = visible;
    onSourcesVisibilityChanged();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hideSources?.cancel();
    field.dispose();
    catalog.dispose();
    keyword.dispose();
    lists.dispose();
    dropdown.dispose();
  }
}
