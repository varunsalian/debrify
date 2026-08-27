import 'package:flutter/material.dart';
import 'deep_link_service.dart';
import 'debrid_service.dart';
import 'torbox_service.dart';
import 'premiumize_service.dart';
import 'alldebrid_service.dart';
import 'storage_service.dart';
import '../models/rd_torrent.dart';
import '../models/torbox_torrent.dart';
import '../widgets/not_cached_dialog.dart';
import '../features/pikpak/data/api_service.dart';

/// Handles incoming magnet links and shared URLs, routing them to appropriate debrid service
class MagnetLinkHandler {
  final BuildContext context;
  final Function(RDTorrent torrent)? onRealDebridAdded;
  final Function(TorboxTorrent torrent)? onTorboxAdded;
  final Function()? onPikPakAdded;
  final Function()? onPremiumizeAdded;
  final Function()? onAllDebridAdded;
  final Function(
    Map<String, dynamic> result,
    String torrentName,
    String apiKey,
  )?
  onRealDebridResult;
  final Function(TorboxTorrent torrent)? onTorboxResult;
  final Function(String fileId, String fileName)? onPikPakResult;
  // URL handling callbacks
  final Function(Map<String, dynamic> result)? onRealDebridUrlResult;
  final Function(int webDownloadId, String fileName)? onTorboxUrlResult;
  final Function()? onAllDebridUrlResult;

  /// Injected rather than reached for: this is one of the callers that already
  /// has a constructor, so it takes the dependency properly instead of going
  /// through [AppServices].
  final PikPakApiService pikpak;

  MagnetLinkHandler({
    required this.context,
    required this.pikpak,
    this.onRealDebridAdded,
    this.onTorboxAdded,
    this.onPikPakAdded,
    this.onPremiumizeAdded,
    this.onAllDebridAdded,
    this.onRealDebridResult,
    this.onTorboxResult,
    this.onPikPakResult,
    this.onRealDebridUrlResult,
    this.onTorboxUrlResult,
    this.onAllDebridUrlResult,
  });

  /// Process a magnet link
  Future<void> handleMagnetLink(String magnetUri) async {
    // Extract infohash and torrent name
    final infohash = DeepLinkService.extractInfohash(magnetUri);
    if (infohash == null) {
      _showError('Invalid magnet link: Could not extract infohash');
      return;
    }

    final torrentName =
        DeepLinkService.extractTorrentName(magnetUri) ?? 'Magnet Link';

    // Check which services are configured
    final services = await DeepLinkService.getConfiguredServices();

    if (!services.hasAny) {
      _showError(
        'No debrid service configured.\nPlease configure RealDebrid, Torbox, PikPak, Premiumize, or AllDebrid in Settings.',
      );
      return;
    }

    // If multiple services are configured, show selection dialog
    if (services.hasMultiple) {
      _showServiceSelectionDialog(magnetUri, infohash, torrentName, services);
    } else if (services.hasOnlyRealDebrid) {
      await _addToRealDebrid(magnetUri, infohash, torrentName);
    } else if (services.hasOnlyTorbox) {
      await _addToTorbox(magnetUri, infohash, torrentName);
    } else if (services.hasOnlyPikPak) {
      await _addToPikPak(magnetUri, infohash, torrentName);
    } else if (services.hasOnlyPremiumize) {
      await _addToPremiumize(magnetUri, torrentName);
    } else if (services.hasOnlyAllDebrid) {
      await _addToAllDebrid(magnetUri, torrentName);
    }
  }

  /// Process a shared URL (http/https)
  Future<void> handleSharedUrl(String url) async {
    // Extract filename from URL for display
    final uri = Uri.tryParse(url);
    String displayName = 'Shared Link';
    if (uri != null) {
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        displayName = Uri.decodeComponent(pathSegments.last);
        // Limit display name length
        if (displayName.length > 50) {
          displayName = '${displayName.substring(0, 47)}...';
        }
      }
    }

    // Check which services are configured
    final services = await DeepLinkService.getConfiguredServices();

    if (!services.hasAny) {
      _showError(
        'No debrid service configured.\nPlease configure RealDebrid, Torbox, PikPak, Premiumize, or AllDebrid in Settings.',
      );
      return;
    }

    // If multiple services are configured, show selection dialog
    if (services.hasMultiple) {
      _showUrlServiceSelectionDialog(url, displayName, services);
    } else if (services.hasOnlyRealDebrid) {
      await _addUrlToRealDebrid(url, displayName);
    } else if (services.hasOnlyTorbox) {
      await _addUrlToTorbox(url, displayName);
    } else if (services.hasOnlyPikPak) {
      await _addUrlToPikPak(url, displayName);
    } else if (services.hasOnlyPremiumize) {
      await _addUrlToPremiumize(url, displayName);
    } else if (services.hasOnlyAllDebrid) {
      await _addUrlToAllDebrid(url, displayName);
    }
  }

  /// Show dialog to select between services for URL
  void _showUrlServiceSelectionDialog(
    String url,
    String displayName,
    ConfiguredServices services,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Which service would you like to use for this link?'),
            const SizedBox(height: 8),
            Text(
              displayName,
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (services.hasRealDebrid)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addUrlToRealDebrid(url, displayName);
              },
              icon: const Icon(Icons.cloud_download),
              label: const Text('RealDebrid'),
            ),
          if (services.hasTorbox)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addUrlToTorbox(url, displayName);
              },
              icon: const Icon(Icons.flash_on),
              label: const Text('Torbox'),
            ),
          if (services.hasPikPak)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addUrlToPikPak(url, displayName);
              },
              icon: const Icon(Icons.cloud_circle),
              label: const Text('PikPak'),
            ),
          if (services.hasPremiumize)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addUrlToPremiumize(url, displayName);
              },
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Premiumize'),
            ),
          if (services.hasAllDebrid)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addUrlToAllDebrid(url, displayName);
              },
              icon: const Icon(Icons.all_inclusive_rounded),
              label: const Text('AllDebrid'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Add URL to RealDebrid (unrestrict link)
  Future<void> _addUrlToRealDebrid(String url, String displayName) async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('RealDebrid API key not configured');
      return;
    }

    _showLoadingDialog(displayName, 'RealDebrid');

    try {
      final result = await DebridService.unrestrictLink(apiKey, url);

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      final downloadUrl = result['download']?.toString() ?? '';
      final filename = result['filename']?.toString() ?? displayName;

      if (downloadUrl.isEmpty) {
        _showError('RealDebrid could not unrestrict this link');
        return;
      }

      // Use callback if available
      if (onRealDebridUrlResult != null) {
        await onRealDebridUrlResult!(result);
      } else {
        // Fallback: show success with filename
        _showSuccess('Link added to RealDebrid: $filename');
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      _showError('Error adding to RealDebrid: $e');
    }
  }

  /// Add URL to Torbox (web download)
  Future<void> _addUrlToTorbox(String url, String displayName) async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('Torbox API key not configured');
      return;
    }

    _showLoadingDialog(displayName, 'Torbox');

    try {
      final result = await TorboxService.createWebDownload(
        apiKey: apiKey,
        link: url,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = (result['error'] ?? result['detail'] ?? '').toString();
        _showError(
          error.isEmpty ? 'Failed to create web download on Torbox' : error,
        );
        return;
      }

      final webDownloadId = (result['data']?['webdownload_id'] as num?)
          ?.toInt();
      final name = result['data']?['name']?.toString() ?? displayName;

      if (webDownloadId == null) {
        _showError('Web download added but missing ID in response');
        return;
      }

      // Use callback if available
      if (onTorboxUrlResult != null) {
        await onTorboxUrlResult!(webDownloadId, name);
      } else {
        // Fallback: show success
        _showSuccess('Link added to Torbox: $name');
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      _showError('Error adding to Torbox: $e');
    }
  }

  /// Add URL to PikPak (offline download)
  Future<void> _addUrlToPikPak(String url, String displayName) async {
    final isAuth = await pikpak.isAuthenticated();
    if (!isAuth) {
      _showError('PikPak not configured. Please login in Settings.');
      return;
    }

    _showLoadingDialog(displayName, 'PikPak');

    try {
      // Get parent folder ID
      final parentFolderId = await StorageService.getPikPakRestrictedFolderId();

      // Find or create subfolder (reuse torrents folder for shared URLs)
      String? subFolderId;
      try {
        subFolderId = await pikpak.findOrCreateSubfolder(
          folderName: 'debrify-torrents',
          parentFolderId: parentFolderId,
          getCachedId: StorageService.getPikPakTorrentsFolderId,
          setCachedId: StorageService.setPikPakTorrentsFolderId,
        );
      } catch (e) {
        if (e.toString().contains('RESTRICTED_FOLDER_DELETED')) {
          if (!context.mounted) return;
          Navigator.of(context).pop();
          await pikpak.logout();
          if (context.mounted) {
            _showError(
              'Restricted folder was deleted. You have been logged out.',
            );
          }
          return;
        }
        subFolderId = parentFolderId;
      }

      final result = await pikpak.addOfflineDownload(
        url,
        parentFolderId: subFolderId,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Extract file ID and name
      String? fileId;
      String? fileName;
      fileId = result.destinationId;
      fileName = result.name.isNotEmpty ? result.name : displayName;

      // Use post-action handling if available. Without a drive entry there is
      // nothing for the post-action to open, so fall through to the snackbar.
      if (onPikPakResult != null && fileId != null) {
        await onPikPakResult!(fileId, fileName);
      } else {
        _showSuccess('Link added to PikPak: $fileName');
        if (onPikPakAdded != null) {
          onPikPakAdded!();
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();

      final folderExists = await pikpak
          .verifyRestrictedFolderExists();
      if (!folderExists) {
        await pikpak.logout();
        if (context.mounted) {
          _showError(
            'Restricted folder was deleted. You have been logged out.',
          );
        }
        return;
      }

      _showError('Error adding to PikPak: $e');
    }
  }

  /// Show dialog to select between services
  void _showServiceSelectionDialog(
    String magnetUri,
    String infohash,
    String torrentName,
    ConfiguredServices services,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Which service would you like to use for this magnet link?',
            ),
            const SizedBox(height: 8),
            Text(
              torrentName,
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (services.hasRealDebrid)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addToRealDebrid(magnetUri, infohash, torrentName);
              },
              icon: const Icon(Icons.cloud_download),
              label: const Text('RealDebrid'),
            ),
          if (services.hasTorbox)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addToTorbox(magnetUri, infohash, torrentName);
              },
              icon: const Icon(Icons.flash_on),
              label: const Text('Torbox'),
            ),
          if (services.hasPikPak)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addToPikPak(magnetUri, infohash, torrentName);
              },
              icon: const Icon(Icons.cloud_circle),
              label: const Text('PikPak'),
            ),
          if (services.hasPremiumize)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addToPremiumize(magnetUri, torrentName);
              },
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Premiumize'),
            ),
          if (services.hasAllDebrid)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _addToAllDebrid(magnetUri, torrentName);
              },
              icon: const Icon(Icons.all_inclusive_rounded),
              label: const Text('AllDebrid'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Add magnet link to RealDebrid
  Future<void> _addToRealDebrid(
    String magnetUri,
    String infohash,
    String torrentName,
  ) async {
    // Get API key
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('RealDebrid API key not configured');
      return;
    }

    _showLoadingDialog(torrentName, 'RealDebrid');

    try {
      final result = await DebridService.addTorrentToDebrid(apiKey, magnetUri);

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Use the same post-action handling as torrent search
      if (onRealDebridResult != null) {
        await onRealDebridResult!(result, torrentName, apiKey);
      } else {
        // Fallback: just show success and navigate to RD tab
        final torrentId = result['torrentId'];
        if (torrentId != null) {
          final torrent = await DebridService.getTorrentInfo(apiKey, torrentId);
          final rdTorrent = RDTorrent.fromJson(torrent);

          _showSuccess('Successfully added to RealDebrid');

          if (onRealDebridAdded != null) {
            onRealDebridAdded!(rdTorrent);
          }
        } else {
          _showSuccess('Successfully added to RealDebrid');
        }
      }
    } on TorrentNotCachedException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final keep = await showNotCachedDialog(context, 'Real-Debrid');
      if (!keep) {
        await DebridService.deleteTorrent(e.apiKey, e.torrentId);
        return;
      }
      if (context.mounted) {
        _showSuccess(
          'Added — it will download on Real-Debrid. Play it once ready.',
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      _showError('Error adding to RealDebrid: $e');
    }
  }

  /// Add magnet link to Torbox
  Future<void> _addToTorbox(
    String magnetUri,
    String infohash,
    String torrentName,
  ) async {
    // Get API key
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('Torbox API key not configured');
      return;
    }

    _showLoadingDialog(torrentName, 'Torbox');

    try {
      final result = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetUri,
        seed: true,
        allowZip: true,
        addOnlyIfCached: true, // Only add if cached (same as torrent search)
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = (result['error'] ?? '').toString();
        if (error == 'DOWNLOAD_NOT_CACHED') {
          final keep = await showNotCachedDialog(context, 'TorBox');
          if (!keep || !context.mounted) return;
          _showLoadingDialog(torrentName, 'Torbox');
          final queued = await TorboxService.createTorrent(
            apiKey: apiKey,
            magnet: magnetUri,
            seed: true,
            allowZip: true,
            addOnlyIfCached: false,
          );
          if (!context.mounted) return;
          Navigator.of(context).pop();
          if (queued['success'] as bool? ?? false) {
            _showSuccess(
              'Added — it will download on TorBox. Play it once ready.',
            );
          } else {
            final queueError = (queued['error'] ?? '').toString();
            _showError(
              queueError.isEmpty
                  ? 'Failed to add torrent to TorBox.'
                  : queueError,
            );
          }
        } else {
          _showError(
            error.isEmpty ? 'Failed to cache torrent on Torbox.' : error,
          );
        }
        return;
      }

      final torrentId = result['data']?['torrent_id'];
      if (torrentId == null) {
        _showError('Torrent added but missing torrent id in response.');
        return;
      }

      // Fetch full torrent details
      final torrent = await TorboxService.getTorrentById(apiKey, torrentId);

      if (torrent != null) {
        // Use the same post-action handling as torrent search
        if (onTorboxResult != null) {
          await onTorboxResult!(torrent);
        } else {
          // Fallback: just show success and navigate
          _showSuccess('Successfully added to Torbox');
          if (onTorboxAdded != null) {
            onTorboxAdded!(torrent);
          }
        }
      } else {
        _showError(
          'Torbox cached the torrent but details are not ready yet. Check the Torbox tab shortly.',
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      _showError('Error adding to Torbox: $e');
    }
  }

  /// Add magnet link to PikPak
  Future<void> _addToPikPak(
    String magnetUri,
    String infohash,
    String torrentName,
  ) async {
    // Check if authenticated
    final isAuth = await pikpak.isAuthenticated();
    if (!isAuth) {
      _showError('PikPak not configured. Please login in Settings.');
      return;
    }

    _showLoadingDialog(torrentName, 'PikPak');

    try {
      // Get parent folder ID (restricted folder or root)
      final parentFolderId = await StorageService.getPikPakRestrictedFolderId();

      // Find or create "debrify-torrents" subfolder (same as search)
      String? subFolderId;
      try {
        subFolderId = await pikpak.findOrCreateSubfolder(
          folderName: 'debrify-torrents',
          parentFolderId: parentFolderId,
          getCachedId: StorageService.getPikPakTorrentsFolderId,
          setCachedId: StorageService.setPikPakTorrentsFolderId,
        );
        debugPrint('PikPak: Using subfolder ID: $subFolderId');
      } catch (e) {
        // Check if this is the restricted folder deleted error
        if (e.toString().contains('RESTRICTED_FOLDER_DELETED')) {
          debugPrint('PikPak: Detected restricted folder was deleted');
          if (!context.mounted) return;
          Navigator.of(context).pop(); // Close loading dialog
          await pikpak.logout();
          if (context.mounted) {
            _showError(
              'Restricted folder was deleted. You have been logged out.',
            );
          }
          return;
        }
        debugPrint(
          'PikPak: Failed to create subfolder, using parent folder: $e',
        );
        subFolderId = parentFolderId;
      }

      final result = await pikpak.addOfflineDownload(
        magnetUri,
        parentFolderId: subFolderId,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Extract file ID and name from response
      String? fileId;
      String? fileName;
      fileId = result.destinationId;
      fileName = result.name.isNotEmpty ? result.name : torrentName;

      // Use post-action handling if available. Without a drive entry there is
      // nothing for the post-action to open, so fall through to the snackbar.
      if (onPikPakResult != null && fileId != null) {
        await onPikPakResult!(fileId, fileName);
      } else {
        // Fallback: just show success
        _showSuccess('Successfully added to PikPak: $fileName');
        if (onPikPakAdded != null) {
          onPikPakAdded!();
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Check if the error is because the restricted folder was deleted
      final folderExists = await pikpak
          .verifyRestrictedFolderExists();
      if (!folderExists) {
        await pikpak.logout();
        if (context.mounted) {
          _showError(
            'Restricted folder was deleted. You have been logged out.',
          );
        }
        return;
      }

      _showError('Error adding to PikPak: $e');
    }
  }

  /// Add magnet link to Premiumize
  Future<void> _addToPremiumize(String magnetUri, String torrentName) async {
    final apiKey = await StorageService.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('Premiumize API key not configured');
      return;
    }

    try {
      _showLoadingDialog(torrentName, 'Premiumize');
      final cached = await PremiumizeService.isCachedStrict(apiKey, magnetUri);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (!cached) {
        final keep = await showNotCachedDialog(context, 'Premiumize');
        if (!keep || !context.mounted) return;
      }

      _showLoadingDialog(torrentName, 'Premiumize');
      await PremiumizeService.createTransfer(apiKey, magnetUri);

      if (!context.mounted) return;
      Navigator.of(context).pop();

      _showSuccess('Added to Premiumize: $torrentName');
      onPremiumizeAdded?.call();
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showError('Error adding to Premiumize: $e');
    }
  }

  /// Add URL to Premiumize (direct download / unrestrict)
  Future<void> _addUrlToPremiumize(String url, String displayName) async {
    final apiKey = await StorageService.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('Premiumize API key not configured');
      return;
    }

    _showLoadingDialog(displayName, 'Premiumize');

    try {
      await PremiumizeService.createTransfer(apiKey, url);

      if (!context.mounted) return;
      Navigator.of(context).pop();

      _showSuccess('Added to Premiumize: $displayName');
      onPremiumizeAdded?.call();
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showError('Error adding to Premiumize: $e');
    }
  }

  /// Add magnet link to AllDebrid
  Future<void> _addToAllDebrid(String magnetUri, String torrentName) async {
    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('AllDebrid API key not configured');
      return;
    }

    _showLoadingDialog(torrentName, 'AllDebrid');

    try {
      await AllDebridService.addMagnetAndResolveFiles(apiKey, magnetUri);

      if (!context.mounted) return;
      Navigator.of(context).pop();

      _showSuccess('Added to AllDebrid: $torrentName');
      onAllDebridAdded?.call();
    } on AllDebridTorrentNotReadyException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final keep = await showNotCachedDialog(context, 'AllDebrid');
      if (!keep) {
        await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        return;
      }
      if (context.mounted) {
        _showSuccess(
          'Added — it will download on AllDebrid. Play it once ready.',
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showError('Error adding to AllDebrid: $e');
    }
  }

  /// Add URL to AllDebrid (unlock hoster link)
  Future<void> _addUrlToAllDebrid(String url, String displayName) async {
    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('AllDebrid API key not configured');
      return;
    }

    _showLoadingDialog(displayName, 'AllDebrid');

    try {
      // Unlock first to validate the host is supported, then persist it to the
      // saved-links library so it shows up in the Web Downloads view (matching
      // the in-app Add Link flow, and RD/Torbox shared-URL behavior).
      final downloadUrl = await AllDebridService.unlockLink(apiKey, url);
      if (downloadUrl.isEmpty) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        _showError('AllDebrid could not unlock this link');
        return;
      }
      await AllDebridService.saveLink(apiKey, url);

      if (!context.mounted) return;
      Navigator.of(context).pop();

      _showSuccess('Link added to AllDebrid: $displayName');
      // Web links go to the Web Downloads view (not the magnet/Torrents view
      // that onAllDebridAdded targets), so use the dedicated URL callback.
      if (onAllDebridUrlResult != null) {
        onAllDebridUrlResult!();
      } else {
        onAllDebridAdded?.call();
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showError('Error adding to AllDebrid: $e');
    }
  }

  /// Show loading dialog
  void _showLoadingDialog(String torrentName, String service) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Adding to $service...'),
            const SizedBox(height: 8),
            Text(
              torrentName,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Show success message
  void _showSuccess(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show error message
  void _showError(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
