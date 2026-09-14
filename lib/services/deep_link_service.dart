import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/platform_util.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'storage_service.dart';
import 'profiles/desktop_single_instance.dart';
import 'profiles/profile_lock_controller.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/pending_external_action_store.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();

  // These plugins have no tvOS implementation. Sharing intents are mobile
  // only; app_links also supports desktop deep links.
  static bool get _supportsAppLinks => !PlatformUtil.isTvOS;
  static bool get _supportsSharingIntents =>
      !kIsWeb &&
      !PlatformUtil.isTvOS &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
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
  final List<String> _pendingProfileActions = <String>[];
  StreamSubscription<List<String>>? _desktopArgumentsSubscription;

  // ==========================================================================
  // Launch-intent preflight
  //
  // The IPTV startup channel decides which tab to open SYNCHRONOUSLY, in a
  // field initializer, before any async work can answer. The initial link and
  // share used to be read here in initialize() — i.e. after MainPage mounts —
  // so a startup auto-launch would win the race and tune a channel over a
  // magnet the user had just opened the app with.
  //
  // main() therefore resolves both before runApp and CACHES them here.
  // initialize() consumes the cached values rather than reading again: an
  // initial share is consume-once, so a second read would either drop it or
  // deliver it twice.
  // ==========================================================================

  static bool _preflightRan = false;
  static Uri? _preflightUri;
  static List<SharedFile>? _preflightShared;
  static bool _launchedByIntent = false;

  /// True when the app was opened by a link or a share. Read by main() to
  /// suppress the IPTV startup channel — the user's explicit intent wins.
  ///
  /// Recorded as its own flag rather than derived from the cached values:
  /// [initialize] CONSUMES those (nulls them), so a derived getter would start
  /// answering false the moment the link was handled.
  static bool get launchedByIntent => _launchedByIntent;

  /// Read the launch intent once, before runApp. Never throws.
  static Future<void> preflightLaunchIntent() async {
    if (_preflightRan) return;
    _preflightRan = true;
    try {
      if (_supportsAppLinks) {
        _preflightUri = await DeepLinkService()._appLinks.getInitialLink();
      }
    } catch (_) {
      debugPrint('Deep link preflight (link) failed');
    }
    try {
      if (_supportsSharingIntents) {
        _preflightShared = await FlutterSharingIntent.instance
            .getInitialSharing();
      }
    } catch (_) {
      debugPrint('Deep link preflight (share) failed');
    }
    _launchedByIntent =
        _preflightUri != null || (_preflightShared?.isNotEmpty ?? false);
  }

  /// Once profile bootstrap has installed the device vault, move cold-launch
  /// links and pre-profile desktop arguments out of process memory. They are
  /// still not assigned to a profile until the user unlocks one locally.
  static Future<void> persistPreflightActions() async {
    if (!ProfileRuntime.isProfileCommitted) return;
    final values = <String>[];
    final uri = _preflightUri;
    if (uri != null && _isSupportedExternalValue(uri.toString())) {
      values.add(uri.toString());
      _preflightUri = null;
    }
    final shared = _preflightShared;
    if (shared != null) {
      for (final file in shared.take(32)) {
        final value = file.value?.trim();
        if (value != null && _isSupportedExternalValue(value)) {
          values.add(value);
        }
      }
      _preflightShared = null;
    }
    for (final arguments in DesktopSingleInstance.takePendingArguments()) {
      values.addAll(
        arguments.where(
          (value) =>
              value.length <= 16 * 1024 &&
              _isSupportedExternalValue(value.trim()),
        ),
      );
    }
    if (values.isNotEmpty) {
      await PendingExternalActionStore.enqueueAll(values);
    }
  }

  /// Initialize deep link listening
  Future<void> initialize() async {
    _desktopArgumentsSubscription ??= DesktopSingleInstance.forwardedArguments
        .listen(enqueueExternalArguments);
    for (final arguments in DesktopSingleInstance.takePendingArguments()) {
      enqueueExternalArguments(arguments);
    }
    // Handle initial link if app was opened via magnet link
    try {
      // Consume the preflight's read when there was one — getInitialLink is
      // not guaranteed to answer twice, and the share below definitely isn't.
      final Uri? initialUri;
      if (_preflightRan) {
        initialUri = _preflightUri;
        _preflightUri = null;
      } else {
        initialUri = _supportsAppLinks
            ? await _appLinks.getInitialLink()
            : null;
      }
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (_) {
      debugPrint('Failed to get initial app link');
    }

    // Listen for incoming links while app is running
    if (_supportsAppLinks && _linkSubscription == null) {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          _handleUri(uri);
        },
        onError: (_) {
          debugPrint('Deep link stream error');
        },
      );
    }

    // Handle initial shared content if app was opened via share
    try {
      final List<SharedFile> initialShared;
      if (_preflightRan) {
        initialShared = _preflightShared ?? const [];
        _preflightShared = null;
      } else {
        initialShared = _supportsSharingIntents
            ? await FlutterSharingIntent.instance.getInitialSharing()
            : const [];
      }
      if (initialShared.isNotEmpty) {
        _processSharedFiles(initialShared);
      }
    } catch (_) {
      debugPrint('Failed to get initial shared content');
    }

    // Listen for incoming shared content while app is running
    if (_supportsSharingIntents && _sharedMediaSubscription == null) {
      _sharedMediaSubscription = FlutterSharingIntent.instance
          .getMediaStream()
          .listen(
            (List<SharedFile> files) {
              _processSharedFiles(files);
            },
            onError: (_) {
              debugPrint('Share intent stream error');
            },
          );
    }
    await _drainPendingProfileActions();
  }

  /// Desktop secondary launches and platform callbacks share this bounded
  /// queue. ProfileGate drains it only after local profile authorization.
  void enqueueExternalArguments(List<String> arguments) {
    final accepted = <String>[];
    for (final argument in arguments.take(32)) {
      final value = argument.trim();
      if (value.length > 16 * 1024 || !_isSupportedExternalValue(value)) {
        continue;
      }
      accepted.add(value);
    }
    if (!_profileMayDispatch && ProfileRuntime.isProfileCommitted) {
      unawaited(PendingExternalActionStore.enqueueAll(accepted));
      return;
    }
    for (final value in accepted) {
      if (_pendingProfileActions.length == 32) {
        _pendingProfileActions.removeAt(0);
      }
      _pendingProfileActions.add(value);
    }
    unawaited(_drainPendingProfileActions());
  }

  void onProfileUnlocked() => unawaited(_drainPendingProfileActions());

  bool get _profileMayDispatch =>
      !ProfileRuntime.isProfileCommitted ||
      ProfileLockController.instance.lockedProfileId.value == null;

  Future<void> _drainPendingProfileActions() async {
    if (!_profileMayDispatch ||
        (onMagnetLinkReceived == null &&
            onUrlShared == null &&
            onStremioAddonReceived == null)) {
      return;
    }
    if (ProfileRuntime.isProfileCommitted) {
      try {
        _pendingProfileActions.addAll(await PendingExternalActionStore.take());
        while (_pendingProfileActions.length > 32) {
          _pendingProfileActions.removeAt(0);
        }
      } catch (_) {
        debugPrint('Pending external actions could not be opened');
      }
    }
    final pending = List<String>.from(_pendingProfileActions);
    _pendingProfileActions.clear();
    for (final value in pending) {
      final uri = Uri.tryParse(value);
      if (uri != null) _handleUri(uri);
    }
  }

  static bool _isSupportedExternalValue(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        const <String>{
          'magnet',
          'stremio',
          'http',
          'https',
        }.contains(uri.scheme);
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
    if (!_profileMayDispatch) {
      enqueueExternalArguments(<String>[uri.toString()]);
      return;
    }
    debugPrint('Received deep link scheme=${uri.scheme}');

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
    debugPrint('Magnet link detected');

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
        debugPrint('Ignoring recently processed duplicate magnet link');
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
    debugPrint('Stremio addon link detected');

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
      debugPrint('Could not extract a Stremio manifest URL');
    }
  }

  /// Handle Stremio manifest URL
  void _handleStremioManifestUrl(String manifestUrl) {
    if (!_profileMayDispatch) {
      enqueueExternalArguments(<String>[manifestUrl]);
      return;
    }
    debugPrint('Processing Stremio manifest URL');

    // Deduplication check
    final now = DateTime.now();
    final lastProcessed = _recentlyProcessedUrls[manifestUrl];

    if (lastProcessed != null) {
      final timeSinceProcessed = now.difference(lastProcessed);
      if (timeSinceProcessed < _deduplicationWindow) {
        debugPrint(
          'Ignoring duplicate Stremio manifest (processed ${timeSinceProcessed.inSeconds}s ago)',
        );
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
    debugPrint('Received shared text');

    // Extract URL from the shared text
    final url = extractUrl(text);
    if (url == null) {
      debugPrint('No valid URL found in shared text');
      return;
    }

    debugPrint('Extracted supported URL');
    if (!_profileMayDispatch) {
      enqueueExternalArguments(<String>[url]);
      return;
    }

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
          debugPrint(
            'Ignoring duplicate URL (processed ${timeSinceProcessed.inSeconds}s ago)',
          );
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
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('magnet:') ||
        text.startsWith('stremio://')) {
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
    } catch (_) {
      debugPrint('Failed to parse magnet identifier');
      return null;
    }
  }

  /// Get torrent name from magnet URI if available
  static String? extractTorrentName(String magnetUri) {
    try {
      final uri = Uri.parse(magnetUri);
      return uri.queryParameters['dn']; // 'dn' = display name
    } catch (_) {
      debugPrint('Failed to parse torrent display name');
      return null;
    }
  }

  /// Check which debrid services are configured
  static Future<ConfiguredServices> getConfiguredServices() async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    final premiumizeEnabled =
        await StorageService.getPremiumizeIntegrationEnabled();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final allDebridEnabled =
        await StorageService.getAllDebridIntegrationEnabled();

    final hasRealDebrid = rdKey != null && rdKey.isNotEmpty && rdEnabled;
    final hasTorbox =
        torboxKey != null && torboxKey.isNotEmpty && torboxEnabled;
    final hasPremiumize =
        premiumizeKey != null && premiumizeKey.isNotEmpty && premiumizeEnabled;
    final hasAllDebrid =
        allDebridKey != null && allDebridKey.isNotEmpty && allDebridEnabled;

    return ConfiguredServices(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
      hasPikPak: pikpakEnabled,
      hasPremiumize: hasPremiumize,
      hasAllDebrid: hasAllDebrid,
    );
  }

  /// Dispose resources
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _sharedMediaSubscription?.cancel();
    _sharedMediaSubscription = null;
    _desktopArgumentsSubscription?.cancel();
    _desktopArgumentsSubscription = null;
    _recentlyProcessedMagnets.clear();
    _recentlyProcessedUrls.clear();
  }
}

/// Model for configured debrid services
class ConfiguredServices {
  final bool hasRealDebrid;
  final bool hasTorbox;
  final bool hasPikPak;
  final bool hasPremiumize;
  final bool hasAllDebrid;

  ConfiguredServices({
    required this.hasRealDebrid,
    required this.hasTorbox,
    required this.hasPikPak,
    this.hasPremiumize = false,
    this.hasAllDebrid = false,
  });

  bool get hasAny =>
      hasRealDebrid || hasTorbox || hasPikPak || hasPremiumize || hasAllDebrid;
  bool get hasMultiple =>
      [
        hasRealDebrid,
        hasTorbox,
        hasPikPak,
        hasPremiumize,
        hasAllDebrid,
      ].where((e) => e).length >
      1;
  bool get hasOnlyRealDebrid =>
      hasRealDebrid &&
      !hasTorbox &&
      !hasPikPak &&
      !hasPremiumize &&
      !hasAllDebrid;
  bool get hasOnlyTorbox =>
      !hasRealDebrid &&
      hasTorbox &&
      !hasPikPak &&
      !hasPremiumize &&
      !hasAllDebrid;
  bool get hasOnlyPikPak =>
      !hasRealDebrid &&
      !hasTorbox &&
      hasPikPak &&
      !hasPremiumize &&
      !hasAllDebrid;
  bool get hasOnlyPremiumize =>
      !hasRealDebrid &&
      !hasTorbox &&
      !hasPikPak &&
      hasPremiumize &&
      !hasAllDebrid;
  bool get hasOnlyAllDebrid =>
      !hasRealDebrid &&
      !hasTorbox &&
      !hasPikPak &&
      !hasPremiumize &&
      hasAllDebrid;

  // Legacy getter for backward compatibility
  bool get hasBoth => hasRealDebrid && hasTorbox;
}
