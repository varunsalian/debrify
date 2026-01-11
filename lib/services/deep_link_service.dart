import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'storage_service.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<List<SharedFile>>? _sharedMediaSubscription;

  // Callback function to handle magnet links
  // This will be set from the main app
  Future<void> Function(String magnetUri)? onMagnetLinkReceived;

  // Callback function to handle shared URLs (http/https)
  Future<void> Function(String url)? onUrlShared;

  // Callback function to handle Stremio addon URLs
  Future<void> Function(String manifestUrl)? onStremioAddonReceived;

  // Track recently processed links to avoid duplicates
  final Map<String, DateTime> _recentlyProcessedMagnets = {};
  final Map<String, DateTime> _recentlyProcessedUrls = {};
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

    // Handle initial shared content if app was opened via share
    try {
      final initialShared = await FlutterSharingIntent.instance.getInitialSharing();
      if (initialShared.isNotEmpty) {
        _processSharedFiles(initialShared);
      }
    } catch (e) {
      debugPrint('Failed to get initial shared content: $e');
    }

    // Listen for incoming shared content while app is running
    _sharedMediaSubscription = FlutterSharingIntent.instance.getMediaStream().listen(
      (List<SharedFile> files) {
        _processSharedFiles(files);
      },
      onError: (err) {
        debugPrint('Share intent error: $err');
      },
    );
  }

  /// Process shared files and extract text/URLs
  void _processSharedFiles(List<SharedFile> files) {
    for (final file in files) {
      // The value property contains the shared content (text, URL, or file path)
      final value = file.value;
      if (value != null && value.isNotEmpty) {
        // Check if it's a text share (URL or text content)
        if (file.type == SharedMediaType.TEXT ||
            file.type == SharedMediaType.URL ||
            value.startsWith('http://') ||
            value.startsWith('https://') ||
            value.startsWith('magnet:') ||
            value.startsWith('stremio://')) {
          _handleSharedText(value);
        }
      }
    }
  }

  /// Handle incoming URI (magnet links, stremio addons)
  void _handleUri(Uri uri) {
    debugPrint('Received deep link: $uri');

    if (uri.scheme == 'magnet') {
      _handleMagnetUri(uri);
    } else if (uri.scheme == 'stremio') {
      _handleStremioUri(uri);
    } else if (uri.scheme == 'https' || uri.scheme == 'http') {
      // Check if it's a Stremio manifest URL
      if (uri.path.endsWith('manifest.json')) {
        _handleStremioManifestUrl(uri.toString());
      }
    }
  }

  /// Handle magnet URI
  void _handleMagnetUri(Uri uri) {
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

  /// Handle Stremio addon URI (stremio://...)
  void _handleStremioUri(Uri uri) {
    debugPrint('Stremio addon link detected: $uri');

    // Extract manifest URL from stremio:// URI
    // Format can be:
    // - stremio://addon/https%3A%2F%2Fexample.com%2Fmanifest.json
    // - stremio://example.com/manifest.json
    // - stremio://addon?url=https://example.com/manifest.json

    String? manifestUrl;

    // Try to extract from path (URL-encoded manifest URL after /addon/)
    final path = uri.path;
    if (path.startsWith('/addon/') || path.startsWith('addon/')) {
      final encodedUrl = path.replaceFirst(RegExp(r'^/?addon/'), '');
      manifestUrl = Uri.decodeComponent(encodedUrl);
    } else if (path.startsWith('/')) {
      // Direct path format: stremio://example.com/path/manifest.json
      // Reconstruct as https URL
      final host = uri.host;
      if (host.isNotEmpty) {
        manifestUrl = 'https://$host$path';
      }
    }

    // Try query parameter format
    if (manifestUrl == null || manifestUrl.isEmpty) {
      manifestUrl = uri.queryParameters['url'];
    }

    // Fallback: try the whole thing after stremio://
    if (manifestUrl == null || manifestUrl.isEmpty) {
      final fullPath = uri.toString().replaceFirst('stremio://', '');
      if (fullPath.contains('manifest.json')) {
        // Decode and ensure it's a proper URL
        manifestUrl = Uri.decodeComponent(fullPath);
        if (!manifestUrl.startsWith('http')) {
          manifestUrl = 'https://$manifestUrl';
        }
      }
    }

    if (manifestUrl != null && manifestUrl.isNotEmpty) {
      _handleStremioManifestUrl(manifestUrl);
    } else {
      debugPrint('Could not extract manifest URL from Stremio link: $uri');
    }
  }

  /// Handle Stremio manifest URL
  void _handleStremioManifestUrl(String manifestUrl) {
    debugPrint('Processing Stremio manifest URL: $manifestUrl');

    // Deduplication check
    final now = DateTime.now();
    final lastProcessed = _recentlyProcessedUrls[manifestUrl];

    if (lastProcessed != null) {
      final timeSinceProcessed = now.difference(lastProcessed);
      if (timeSinceProcessed < _deduplicationWindow) {
        debugPrint('Ignoring duplicate Stremio manifest (processed ${timeSinceProcessed.inSeconds}s ago)');
        return;
      }
    }

    // Clean up old entries
    _recentlyProcessedUrls.removeWhere((key, value) {
      return now.difference(value) > _deduplicationWindow;
    });

    // Mark as processed
    _recentlyProcessedUrls[manifestUrl] = now;

    if (onStremioAddonReceived != null) {
      onStremioAddonReceived!(manifestUrl);
    } else {
      debugPrint('No Stremio addon handler registered');
    }
  }

  /// Handle shared text (can contain URLs or magnet links)
  void _handleSharedText(String text) {
    debugPrint('Received shared text: $text');

    // Extract URL from the shared text
    final url = extractUrl(text);
    if (url == null) {
      debugPrint('No valid URL found in shared text');
      return;
    }

    debugPrint('Extracted URL: $url');

    // Check if it's a magnet link
    if (url.startsWith('magnet:')) {
      _handleUri(Uri.parse(url));
      return;
    }

    // Check if it's a stremio:// link
    if (url.startsWith('stremio://')) {
      _handleUri(Uri.parse(url));
      return;
    }

    // Check if it's an HTTP/HTTPS URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // Check if it's a Stremio manifest URL
      if (url.contains('manifest.json')) {
        _handleStremioManifestUrl(url);
        return;
      }

      // Deduplication check
      final now = DateTime.now();
      final lastProcessed = _recentlyProcessedUrls[url];

      if (lastProcessed != null) {
        final timeSinceProcessed = now.difference(lastProcessed);
        if (timeSinceProcessed < _deduplicationWindow) {
          debugPrint('Ignoring duplicate URL (processed ${timeSinceProcessed.inSeconds}s ago)');
          return;
        }
      }

      // Clean up old entries
      _recentlyProcessedUrls.removeWhere((key, value) {
        return now.difference(value) > _deduplicationWindow;
      });

      // Mark as processed
      _recentlyProcessedUrls[url] = now;

      if (onUrlShared != null) {
        onUrlShared!(url);
      } else {
        debugPrint('No URL share handler registered');
      }
    }
  }

  /// Extract URL from text (handles cases where URL is embedded in other text)
  static String? extractUrl(String text) {
    // Trim whitespace
    text = text.trim();

    // If the entire text is a URL, return it
    if (text.startsWith('http://') || text.startsWith('https://') ||
        text.startsWith('magnet:') || text.startsWith('stremio://')) {
      // Find the end of the URL (first whitespace or end of string)
      final endIndex = text.indexOf(RegExp(r'\s'));
      return endIndex == -1 ? text : text.substring(0, endIndex);
    }

    // Try to find a URL in the text using regex
    final urlRegex = RegExp(
      r'(https?://[^\s]+|magnet:\?[^\s]+|stremio://[^\s]+)',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
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
    final pikpakEnabled = await StorageService.getPikPakEnabled();

    final hasRealDebrid = rdKey != null &&
                          rdKey.isNotEmpty &&
                          rdEnabled;
    final hasTorbox = torboxKey != null &&
                      torboxKey.isNotEmpty &&
                      torboxEnabled;

    return ConfiguredServices(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
      hasPikPak: pikpakEnabled,
    );
  }

  /// Dispose resources
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _sharedMediaSubscription?.cancel();
    _sharedMediaSubscription = null;
    _recentlyProcessedMagnets.clear();
    _recentlyProcessedUrls.clear();
  }
}

/// Model for configured debrid services
class ConfiguredServices {
  final bool hasRealDebrid;
  final bool hasTorbox;
  final bool hasPikPak;

  ConfiguredServices({
    required this.hasRealDebrid,
    required this.hasTorbox,
    required this.hasPikPak,
  });

  bool get hasAny => hasRealDebrid || hasTorbox || hasPikPak;
  bool get hasMultiple => [hasRealDebrid, hasTorbox, hasPikPak].where((e) => e).length > 1;
  bool get hasOnlyRealDebrid => hasRealDebrid && !hasTorbox && !hasPikPak;
  bool get hasOnlyTorbox => !hasRealDebrid && hasTorbox && !hasPikPak;
  bool get hasOnlyPikPak => !hasRealDebrid && !hasTorbox && hasPikPak;

  // Legacy getters for backward compatibility
  bool get hasBoth => hasRealDebrid && hasTorbox;
}
