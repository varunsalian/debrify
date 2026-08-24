import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/main_page_bridge.dart';

/// Stable metadata for a destination that can appear in the TV/desktop
/// sidebar. [id] is the persisted identity; [tabIndex] is the app's existing
/// routing identity and must never be persisted as a visible-list position.
class SidebarDestination {
  final String id;
  final int tabIndex;
  final String defaultLabel;
  final String section;
  final IconData icon;

  const SidebarDestination({
    required this.id,
    required this.tabIndex,
    required this.defaultLabel,
    required this.section,
    required this.icon,
  });
}

/// Every destination that can appear in the Android TV or wide-window
/// sidebar, in the exact order used before sidebar customization existed.
/// Availability is still decided by MainPage's integration/profile policy;
/// this catalog only controls the relative order of destinations that survive
/// that filtering.
const List<SidebarDestination> sidebarDestinations = <SidebarDestination>[
  SidebarDestination(
    id: 'search',
    tabIndex: MainTab.search,
    defaultLabel: 'Search',
    section: 'Main',
    icon: Icons.search_rounded,
  ),
  SidebarDestination(
    id: 'home',
    tabIndex: MainTab.home,
    defaultLabel: 'Home',
    section: 'Main',
    icon: Icons.home_rounded,
  ),
  SidebarDestination(
    id: 'discover',
    tabIndex: MainTab.discover,
    defaultLabel: 'Discover',
    section: 'Main',
    icon: Icons.explore_rounded,
  ),
  SidebarDestination(
    id: 'calendar',
    tabIndex: MainTab.calendar,
    defaultLabel: 'Calendar',
    section: 'Main',
    icon: Icons.calendar_month_rounded,
  ),
  SidebarDestination(
    id: 'downloads',
    tabIndex: MainTab.downloads,
    defaultLabel: 'Downloads',
    section: 'Main',
    icon: Icons.download_for_offline_rounded,
  ),
  SidebarDestination(
    id: 'iptv',
    tabIndex: MainTab.iptv,
    defaultLabel: 'IPTV',
    section: 'Browse',
    icon: Icons.live_tv_rounded,
  ),
  SidebarDestination(
    id: 'youtube',
    tabIndex: MainTab.youtube,
    defaultLabel: 'YouTube',
    section: 'Browse',
    icon: Icons.ondemand_video_rounded,
  ),
  SidebarDestination(
    id: 'cloud',
    tabIndex: MainTab.cloud,
    defaultLabel: 'Cloud',
    section: 'Library',
    icon: Icons.cloud_rounded,
  ),
  SidebarDestination(
    id: 'debrify_tv',
    tabIndex: MainTab.debrifyTv,
    defaultLabel: 'Debrify TV',
    section: 'TV',
    icon: Icons.tv_rounded,
  ),
  SidebarDestination(
    id: 'stremio_tv',
    tabIndex: MainTab.stremioTv,
    defaultLabel: 'Stremio TV',
    section: 'TV',
    icon: Icons.smart_display_rounded,
  ),
  SidebarDestination(
    id: 'addons',
    tabIndex: MainTab.addons,
    defaultLabel: 'Addons',
    section: 'Setup',
    icon: Icons.extension_rounded,
  ),
  SidebarDestination(
    id: 'settings',
    tabIndex: MainTab.settings,
    defaultLabel: 'Settings',
    section: 'Setup',
    icon: Icons.settings_rounded,
  ),
];

final Map<String, SidebarDestination> sidebarDestinationById =
    Map<String, SidebarDestination>.unmodifiable(<String, SidebarDestination>{
      for (final destination in sidebarDestinations)
        destination.id: destination,
    });

final Map<int, SidebarDestination> sidebarDestinationByTab =
    Map<int, SidebarDestination>.unmodifiable(<int, SidebarDestination>{
      for (final destination in sidebarDestinations)
        destination.tabIndex: destination,
    });

/// Profile-scoped customization shared by Android TV and desktop/tablet
/// sidebars. It deliberately cannot hide destinations: visibility remains the
/// authority of integration settings and profile policy.
class SidebarConfiguration {
  static const int schemaVersion = 1;
  static const int maxLabelRunes = 24;
  static const int maxSerializedBytes = 4096;

  final List<String> order;
  final Map<String, String> labels;

  SidebarConfiguration({
    required Iterable<String> order,
    Map<String, String> labels = const <String, String>{},
  }) : order = List<String>.unmodifiable(_normalizeOrder(order)),
       labels = Map<String, String>.unmodifiable(_normalizeLabels(labels));

  factory SidebarConfiguration.defaults() => SidebarConfiguration(
    order: sidebarDestinations.map((destination) => destination.id),
  );

  /// Parses a stored value. Invalid or future-version data returns null so a
  /// caller can fall back to defaults without partially applying corruption.
  static SidebarConfiguration? tryDecode(String raw) {
    if (utf8.encode(raw).length > maxSerializedBytes) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != schemaVersion) {
        return null;
      }
      final rawOrder = decoded['order'];
      final rawLabels = decoded['labels'];
      if (rawOrder is! List || rawLabels is! Map) return null;

      final order = <String>[];
      final seen = <String>{};
      for (final value in rawOrder) {
        if (value is! String ||
            !sidebarDestinationById.containsKey(value) ||
            !seen.add(value)) {
          return null;
        }
        order.add(value);
      }

      final labels = <String, String>{};
      for (final entry in rawLabels.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String ||
            value is! String ||
            !sidebarDestinationById.containsKey(key)) {
          return null;
        }
        final normalized = normalizeLabel(value);
        if (normalized == null || normalized != value) return null;
        labels[key] = value;
      }
      return SidebarConfiguration(order: order, labels: labels);
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode(<String, Object>{
    'version': schemaVersion,
    'order': order,
    'labels': labels,
  });

  SidebarConfiguration copyWith({
    Iterable<String>? order,
    Map<String, String>? labels,
  }) => SidebarConfiguration(
    order: order ?? this.order,
    labels: labels ?? this.labels,
  );

  String labelForId(String id) =>
      labels[id] ?? sidebarDestinationById[id]?.defaultLabel ?? id;

  String labelForTab(int tabIndex, String fallback) {
    final destination = sidebarDestinationByTab[tabIndex];
    return destination == null ? fallback : labelForId(destination.id);
  }

  /// Applies the saved ranking only after MainPage has decided which tabs are
  /// visible. Unknown future tabs stay reachable and retain their incoming
  /// relative order at the end until the catalog learns about them.
  List<int> orderVisibleTabs(Iterable<int> visibleTabs) {
    final visible = List<int>.of(visibleTabs);
    final rank = <int, int>{};
    for (var i = 0; i < order.length; i++) {
      final destination = sidebarDestinationById[order[i]];
      if (destination != null) rank[destination.tabIndex] = i;
    }
    final incomingRank = <int, int>{
      for (var i = 0; i < visible.length; i++) visible[i]: i,
    };
    visible.sort((a, b) {
      final aRank = rank[a];
      final bRank = rank[b];
      if (aRank != null && bRank != null) return aRank.compareTo(bRank);
      if (aRank != null) return -1;
      if (bRank != null) return 1;
      return incomingRank[a]!.compareTo(incomingRank[b]!);
    });
    return visible;
  }

  bool get isDefault {
    if (labels.isNotEmpty || order.length != sidebarDestinations.length) {
      return false;
    }
    for (var i = 0; i < order.length; i++) {
      if (order[i] != sidebarDestinations[i].id) return false;
    }
    return true;
  }

  static String? normalizeLabel(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty ||
        normalized.runes.length > maxLabelRunes ||
        normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      return null;
    }
    return normalized;
  }

  static List<String> _normalizeOrder(Iterable<String> raw) {
    final result = <String>[];
    final seen = <String>{};
    for (final id in raw) {
      if (sidebarDestinationById.containsKey(id) && seen.add(id)) {
        result.add(id);
      }
    }
    for (final destination in sidebarDestinations) {
      if (seen.add(destination.id)) result.add(destination.id);
    }
    return result;
  }

  static Map<String, String> _normalizeLabels(Map<String, String> raw) {
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final destination = sidebarDestinationById[entry.key];
      final label = normalizeLabel(entry.value);
      if (destination == null ||
          label == null ||
          label == destination.defaultLabel) {
        continue;
      }
      result[entry.key] = label;
    }
    return result;
  }
}
