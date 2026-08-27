import 'package:flutter/material.dart';

import '../features/debrid/descriptor.dart';
import '../screens/alldebrid/alldebrid_files_screen.dart';
import '../screens/debrid_downloads_screen.dart';
import '../features/pikpak/ui/screen.dart';
import '../screens/premiumize/premiumize_files_screen.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import '../screens/webdav/webdav_files_screen.dart';
import '../services/series_source_service.dart';

/// Wiring between a cloud source and the screen that browses it.
///
/// This is the only file allowed to name both a provider and a screen: the
/// cloud hub, the nav rail, and "pick a source from my cloud" all come through
/// here, so adding a provider never touches a screen or a widget.
class CloudSource {
  /// Cloud-hub id space — Real-Debrid is `realdebrid` here, and WebDAV is a
  /// cloud source without being a debrid provider.
  final String id;
  final String displayName;

  /// The provider's own file browser, pushed as a route.
  final Widget Function() browser;

  /// The same browser in select-a-source mode, for providers that support
  /// pinning a cloud file as a bound source. Null when they don't.
  final Widget Function(CloudSourceRequest request)? picker;

  const CloudSource({
    required this.id,
    required this.displayName,
    required this.browser,
    this.picker,
  });
}

/// What the caller wants out of a select-a-source push.
class CloudSourceRequest {
  /// Title to pre-search for, when the provider's browser supports it.
  final String query;
  final Future<void> Function(SeriesSource source) onSelected;

  const CloudSourceRequest({required this.query, required this.onSelected});
}

abstract final class CloudSources {
  static final List<CloudSource> all = [
    CloudSource(
      id: DebridProviders.realDebrid.cloudKey,
      displayName: DebridProviders.realDebrid.displayName,
      browser: () => const DebridDownloadsScreen(isPushedRoute: true),
    ),
    CloudSource(
      id: DebridProviders.torbox.cloudKey,
      displayName: DebridProviders.torbox.displayName,
      browser: () => const TorboxDownloadsScreen(isPushedRoute: true),
    ),
    CloudSource(
      id: DebridProviders.pikpak.cloudKey,
      displayName: DebridProviders.pikpak.displayName,
      browser: () => const PikPakFilesScreen(isPushedRoute: true),
      picker: (request) => PikPakFilesScreen(
        isPushedRoute: true,
        selectSourceMode: true,
        onSourceSelected: request.onSelected,
      ),
    ),
    CloudSource(
      id: DebridProviders.premiumize.cloudKey,
      displayName: DebridProviders.premiumize.displayName,
      browser: () => const PremiumizeFilesScreen(isPushedRoute: true),
      picker: (request) => PremiumizeFilesScreen(
        isPushedRoute: true,
        initialSearchQuery: request.query,
        selectSourceMode: true,
        onSourceSelected: request.onSelected,
      ),
    ),
    CloudSource(
      id: DebridProviders.allDebrid.cloudKey,
      displayName: DebridProviders.allDebrid.displayName,
      browser: () => const AllDebridFilesScreen(isPushedRoute: true),
      picker: (request) => AllDebridFilesScreen(
        isPushedRoute: true,
        initialSearchQuery: request.query,
        selectSourceMode: true,
        onSourceSelected: request.onSelected,
      ),
    ),
    CloudSource(
      id: DebridProviderIds.webdav,
      displayName: 'WebDAV',
      // WebDAV returns a CloudScaffold of its own (Material ancestor + the
      // cloud bloom painted edge-to-edge, SafeArea inside). In pushed mode
      // its toolbar shows a Back button and it registers a pushed-route
      // back handler, so system/remote Back folds the stack.
      browser: () => const WebDavFilesScreen(isPushedRoute: true),
    ),
  ];

  /// The cloud source for a hub id, or null when nothing browses that id.
  static CloudSource? find(String id) {
    for (final source in all) {
      if (source.id == id) return source;
    }
    return null;
  }
}
