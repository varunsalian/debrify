import 'package:flutter/widgets.dart';

/// Card-detail preferences published by the Discover host.
///
/// Every Discover source renders through the shared poster grid, and Home row
/// expansions opt into the same scope. This keeps add-on catalogs and
/// tracker/library sources in lock-step while leaving Search and unrelated
/// standalone See-All grids unchanged.
class DiscoverCardSettingsScope extends InheritedWidget {
  final bool showTypeTags;
  final bool showRatings;
  final bool showTitles;

  const DiscoverCardSettingsScope({
    super.key,
    required this.showTypeTags,
    required this.showRatings,
    required this.showTitles,
    required super.child,
  });

  static DiscoverCardSettingsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiscoverCardSettingsScope>();

  @override
  bool updateShouldNotify(DiscoverCardSettingsScope oldWidget) =>
      showTypeTags != oldWidget.showTypeTags ||
      showRatings != oldWidget.showRatings ||
      showTitles != oldWidget.showTitles;
}
