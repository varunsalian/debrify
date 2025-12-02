import 'package:flutter/material.dart';
import 'deep_link_service.dart';
import 'debrid_service.dart';
import 'torbox_service.dart';
import 'pikpak_api_service.dart';
import 'storage_service.dart';
import '../models/rd_torrent.dart';
import '../models/torbox_torrent.dart';

/// Handles incoming magnet links and routes them to appropriate debrid service
class MagnetLinkHandler {
  final BuildContext context;
  final Function(RDTorrent torrent)? onRealDebridAdded;
  final Function(TorboxTorrent torrent)? onTorboxAdded;
  final Function()? onPikPakAdded;
  final Function(Map<String, dynamic> result, String torrentName, String apiKey)? onRealDebridResult;
  final Function(TorboxTorrent torrent)? onTorboxResult;

  MagnetLinkHandler({
    required this.context,
    this.onRealDebridAdded,
    this.onTorboxAdded,
    this.onPikPakAdded,
    this.onRealDebridResult,
    this.onTorboxResult,
  });

  /// Process a magnet link
  Future<void> handleMagnetLink(String magnetUri) async {
    // Extract infohash and torrent name
    final infohash = DeepLinkService.extractInfohash(magnetUri);
    if (infohash == null) {
      _showError('Invalid magnet link: Could not extract infohash');
      return;
    }

    final torrentName = DeepLinkService.extractTorrentName(magnetUri) ??
                       'Magnet Link';

    // Check which services are configured
    final services = await DeepLinkService.getConfiguredServices();

    if (!services.hasAny) {
      _showError('No debrid service configured.\nPlease configure RealDebrid, Torbox, or PikPak in Settings.');
      return;
    }

    // If multiple services are configured, show selection dialog
    if (services.hasMultiple) {
      _showServiceSelectionDialog(magnetUri, infohash, torrentName, services);
    } else if (services.hasOnlyRealDebrid) {
      // Auto-select RealDebrid
      await _addToRealDebrid(magnetUri, infohash, torrentName);
    } else if (services.hasOnlyTorbox) {
      // Auto-select Torbox
      await _addToTorbox(magnetUri, infohash, torrentName);
    } else if (services.hasOnlyPikPak) {
      // Auto-select PikPak
      await _addToPikPak(magnetUri, infohash, torrentName);
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
            const Text('Which service would you like to use for this magnet link?'),
            const SizedBox(height: 8),
            Text(
              torrentName,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
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
          _showError('Torrent is not cached on Torbox yet. Disable "add only if cached" in settings to force add.');
        } else {
          _showError(error.isEmpty ? 'Failed to cache torrent on Torbox.' : error);
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
        _showError('Torbox cached the torrent but details are not ready yet. Check the Torbox tab shortly.');
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
    final isAuth = await PikPakApiService.instance.isAuthenticated();
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
        subFolderId = await PikPakApiService.instance.findOrCreateSubfolder(
          folderName: 'debrify-torrents',
          parentFolderId: parentFolderId,
          getCachedId: StorageService.getPikPakTorrentsFolderId,
          setCachedId: StorageService.setPikPakTorrentsFolderId,
        );
        print('PikPak: Using subfolder ID: $subFolderId');
      } catch (e) {
        // Check if this is the restricted folder deleted error
        if (e.toString().contains('RESTRICTED_FOLDER_DELETED')) {
          print('PikPak: Detected restricted folder was deleted');
          if (!context.mounted) return;
          Navigator.of(context).pop(); // Close loading dialog
          await PikPakApiService.instance.logout();
          if (context.mounted) {
            _showError(
              'Restricted folder was deleted. You have been logged out.',
            );
          }
          return;
        }
        print('PikPak: Failed to create subfolder, using parent folder: $e');
        subFolderId = parentFolderId;
      }

      final result = await PikPakApiService.instance.addOfflineDownload(
        magnetUri,
        parentFolderId: subFolderId,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Extract file name from response
      String? fileName;
      if (result['file'] != null) {
        fileName = result['file']['name'] ?? torrentName;
      } else if (result['task'] != null) {
        fileName = result['task']['name'] ?? torrentName;
      } else {
        fileName = torrentName;
      }

      _showSuccess('Successfully added to PikPak: $fileName');

      if (onPikPakAdded != null) {
        onPikPakAdded!();
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Check if the error is because the restricted folder was deleted
      final folderExists =
          await PikPakApiService.instance.verifyRestrictedFolderExists();
      if (!folderExists) {
        await PikPakApiService.instance.logout();
        if (context.mounted) {
          _showError('Restricted folder was deleted. You have been logged out.');
        }
        return;
      }

      _showError('Error adding to PikPak: $e');
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
