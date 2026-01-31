import 'package:flutter/material.dart';

/// Sections in the Home screen that can receive focus
enum HomeSection {
  sources,
  favorites,
  iptvFavorites,
  tvFavorites,
  providers,
}

/// Centralized focus state management for Home screen DPAD navigation.
///
/// This controller:
/// - Tracks which section currently has focus
/// - Remembers the last focused index per section
/// - Handles navigation between sections (skipping empty ones)
/// - Provides focus nodes for programmatic focus control
class HomeFocusController extends ChangeNotifier {
  HomeSection _currentSection = HomeSection.sources;

  /// Last focused card index per section
  final Map<HomeSection, int> _lastFocusedIndex = {
    HomeSection.favorites: 0,
    HomeSection.iptvFavorites: 0,
    HomeSection.tvFavorites: 0,
    HomeSection.providers: 0,
  };

  /// Whether each section has focusable items
  final Map<HomeSection, bool> _sectionHasItems = {
    HomeSection.sources: true, // Sources accordion is always present
    HomeSection.favorites: false,
    HomeSection.iptvFavorites: false,
    HomeSection.tvFavorites: false,
    HomeSection.providers: false,
  };

  /// Focus nodes for each section's cards
  final Map<HomeSection, List<FocusNode>> _sectionFocusNodes = {};

  /// Focus node for the sources accordion (set by parent)
  FocusNode? sourcesAccordionFocusNode;

  /// Get the currently focused section
  HomeSection get currentSection => _currentSection;

  /// Register a section's focusable items.
  /// Called by each section widget when its data loads.
  void registerSection(
    HomeSection section, {
    required bool hasItems,
    required List<FocusNode> focusNodes,
  }) {
    _sectionHasItems[section] = hasItems;
    _sectionFocusNodes[section] = focusNodes;

    // Clamp last focused index to valid range
    if (focusNodes.isNotEmpty) {
      final lastIndex = _lastFocusedIndex[section] ?? 0;
      _lastFocusedIndex[section] = lastIndex.clamp(0, focusNodes.length - 1);
    }
  }

  /// Unregister a section (e.g., when widget disposes)
  void unregisterSection(HomeSection section) {
    _sectionHasItems[section] = false;
    _sectionFocusNodes.remove(section);
  }

  /// Get the next visible section (skipping empty ones)
  /// Returns null if there are no more sections below
  HomeSection? getNextSection(HomeSection from) {
    final sections = HomeSection.values;
    final startIndex = sections.indexOf(from);

    for (int i = startIndex + 1; i < sections.length; i++) {
      final section = sections[i];
      if (_sectionHasItems[section] == true) {
        return section;
      }
    }
    return null;
  }

  /// Get the previous visible section (skipping empty ones)
  /// Returns sources if at the top
  HomeSection? getPreviousSection(HomeSection from) {
    final sections = HomeSection.values;
    final startIndex = sections.indexOf(from);

    for (int i = startIndex - 1; i >= 0; i--) {
      final section = sections[i];
      if (section == HomeSection.sources) {
        return section; // Sources is always "visible"
      }
      if (_sectionHasItems[section] == true) {
        return section;
      }
    }
    return HomeSection.sources;
  }

  /// Move focus to a specific section
  /// Optionally specify which index to focus (defaults to last focused)
  void focusSection(HomeSection section, {int? index}) {
    if (section == HomeSection.sources) {
      sourcesAccordionFocusNode?.requestFocus();
      _currentSection = section;
      notifyListeners();
      return;
    }

    final focusNodes = _sectionFocusNodes[section];
    if (focusNodes == null || focusNodes.isEmpty) {
      // Section is empty, try next one
      final next = getNextSection(section);
      if (next != null) {
        focusSection(next, index: index);
      }
      return;
    }

    final targetIndex = index ?? _lastFocusedIndex[section] ?? 0;
    final clampedIndex = targetIndex.clamp(0, focusNodes.length - 1);

    focusNodes[clampedIndex].requestFocus();
    _currentSection = section;
    _lastFocusedIndex[section] = clampedIndex;
    notifyListeners();
  }

  /// Save the last focused index for a section
  void saveLastFocusedIndex(HomeSection section, int index) {
    _lastFocusedIndex[section] = index;
  }

  /// Get the remembered last focused index for a section
  int getLastFocusedIndex(HomeSection section) {
    return _lastFocusedIndex[section] ?? 0;
  }

  /// Check if a section has any focusable items
  bool sectionHasItems(HomeSection section) {
    return _sectionHasItems[section] ?? false;
  }

  /// Get focus nodes for a section
  List<FocusNode>? getFocusNodes(HomeSection section) {
    return _sectionFocusNodes[section];
  }

  /// Navigate to the first available section below sources
  void focusFirstHomeSection() {
    final next = getNextSection(HomeSection.sources);
    if (next != null) {
      focusSection(next, index: 0);
    }
  }

  @override
  void dispose() {
    _sectionFocusNodes.clear();
    super.dispose();
  }
}
