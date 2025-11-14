import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'storage_service.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  // Callback function to handle magnet links
  // This will be set from the main app
  Future<void> Function(String magnetUri)? onMagnetLinkReceived;

  // Track recently processed magnet links to avoid duplicates
  final Map<String, DateTime> _recentlyProcessedMagnets = {};
  static const _deduplicationWindow = Duration(seconds: 30);

  /// Initialize deep link listening
  Future<void> initialize() async {
    // Handle initial link if app was opened via magnet link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('Failed to get initial app link: $e');
    }

    // Listen for incoming links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleUri(uri);
      },
      onError: (err) {
        debugPrint('Deep link error: $err');
      },
    );
  }

  /// Handle incoming URI
  void _handleUri(Uri uri) {
    debugPrint('Received deep link: $uri');

    if (uri.scheme == 'magnet') {
      final magnetUri = uri.toString();
      debugPrint('Magnet link detected: $magnetUri');

      // Extract infohash for deduplication (same torrent can have different magnet URIs)
      final infohash = extractInfohash(magnetUri);
      if (infohash == null) {
        debugPrint('Could not extract infohash from magnet link');
        return;
      }

      // Check if we've already processed this infohash recently
      final now = DateTime.now();
      final lastProcessed = _recentlyProcessedMagnets[infohash];

      if (lastProcessed != null) {
        final timeSinceProcessed = now.difference(lastProcessed);
        if (timeSinceProcessed < _deduplicationWindow) {
          debugPrint('Ignoring duplicate magnet link (infohash: $infohash, processed ${timeSinceProcessed.inSeconds}s ago)');
          return;
        }
      }

      // Clean up old entries from the tracking map
      _recentlyProcessedMagnets.removeWhere((key, value) {
        return now.difference(value) > _deduplicationWindow;
      });

      // Mark this infohash as processed
      _recentlyProcessedMagnets[infohash] = now;

      if (onMagnetLinkReceived != null) {
        onMagnetLinkReceived!(magnetUri);
      } else {
        debugPrint('No magnet link handler registered');
      }
    }
  }

  /// Extract infohash from magnet URI
  /// Example: magnet:?xt=urn:btih:ABCD1234...
  static String? extractInfohash(String magnetUri) {
    try {
      final uri = Uri.parse(magnetUri);

      // Get the 'xt' parameter (exact topic)
      final xt = uri.queryParameters['xt'];
      if (xt == null) return null;

      // Extract infohash from urn:btih:HASH format
      if (xt.startsWith('urn:btih:')) {
        return xt.substring('urn:btih:'.length);
      }

      return null;
    } catch (e) {
      debugPrint('Failed to extract infohash from magnet URI: $e');
      return null;
    }
  }

  /// Get torrent name from magnet URI if available
  static String? extractTorrentName(String magnetUri) {
    try {
      final uri = Uri.parse(magnetUri);
      return uri.queryParameters['dn']; // 'dn' = display name
    } catch (e) {
      debugPrint('Failed to extract torrent name: $e');
      return null;
    }
  }

  /// Check which debrid services are configured
  static Future<ConfiguredServices> getConfiguredServices() async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();

    final hasRealDebrid = rdKey != null &&
                          rdKey.isNotEmpty &&
                          rdEnabled;
    final hasTorbox = torboxKey != null &&
                      torboxKey.isNotEmpty &&
                      torboxEnabled;

    return ConfiguredServices(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
    );
  }

  /// Dispose resources
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _recentlyProcessedMagnets.clear();
  }
}

/// Model for configured debrid services
class ConfiguredServices {
  final bool hasRealDebrid;
  final bool hasTorbox;

  ConfiguredServices({
    required this.hasRealDebrid,
    required this.hasTorbox,
  });

  bool get hasAny => hasRealDebrid || hasTorbox;
  bool get hasBoth => hasRealDebrid && hasTorbox;
  bool get hasOnlyRealDebrid => hasRealDebrid && !hasTorbox;
  bool get hasOnlyTorbox => !hasRealDebrid && hasTorbox;
}
