import 'package:flutter/widgets.dart';

/// Card-detail preferences published by the Discover host.
///
/// Every Discover source renders through the shared poster grid, so one scope
/// keeps add-on catalogs and tracker/library sources in lock-step while leaving
/// standalone See-All and Search grids unchanged.
class DiscoverCardSettingsScope extends InheritedWidget {
  final bool showTypeTags;
  final bool showRatings;

  const DiscoverCardSettingsScope({
    super.key,
    required this.showTypeTags,
    required this.showRatings,
    required super.child,
  });

  static DiscoverCardSettingsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiscoverCardSettingsScope>();

  @override
  bool updateShouldNotify(DiscoverCardSettingsScope oldWidget) =>
      showTypeTags != oldWidget.showTypeTags ||
      showRatings != oldWidget.showRatings;
}
