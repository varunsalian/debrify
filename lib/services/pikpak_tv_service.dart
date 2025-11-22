import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../utils/file_utils.dart';
import 'pikpak_api_service.dart';

/// Service for preparing PikPak torrents for Debrify TV playback.
///
/// Implements a progress threshold strategy:
/// 1. Add magnet via PikPak's addOfflineDownload
/// 2. Wait 1 second - if PHASE_TYPE_COMPLETE, success!
/// 3. Check progress - if >= 50% OR progress delta >= 20%, wait up to 10 more seconds
/// 4. If stuck at low %, trash file and return null (try next torrent)
/// 5. Handle folders (torrent packs) - scan for video files >= 100MB and randomly select one
/// 6. Return streaming URL and title on success
class PikPakTvService {
  static final PikPakTvService instance = PikPakTvService._();
  PikPakTvService._();

  final PikPakApiService _api = PikPakApiService.instance;

  // Minimum video file size (100 MB) to filter out samples/extras
  static const int _minVideoSizeBytes = 100 * 1024 * 1024;

  // Progress thresholds for determining if torrent is worth waiting for
  static const int _progressThreshold = 50;
  static const int _progressDeltaThreshold = 20;

  // Timing constants
  static const Duration _initialWait = Duration(seconds: 1);
  static const Duration _pollInterval = Duration(seconds: 1);
  static const Duration _maxWaitDuration = Duration(seconds: 10);

  /// Try to prepare a torrent for streaming.
  /// Returns {url, title} on success, null if not cached/ready.
  Future<Map<String, String>?> prepareTorrent({
    required String infohash,
    required String torrentName,
    void Function(String)? onLog,
  }) async {
    void log(String message) {
      debugPrint('PikPakTvService: $message');
      onLog?.call(message);
    }

    final normalizedHash = infohash.trim().toLowerCase();
    if (normalizedHash.isEmpty) {
      log('Invalid infohash');
      return null;
    }

    final magnetLink = 'magnet:?xt=urn:btih:$normalizedHash';
    log('Preparing torrent: $torrentName');

    String? fileId;
    String? taskId;

    try {
      // Step 1: Add offline download
      log('Adding magnet to PikPak...');
      final addResponse = await _api.addOfflineDownload(magnetLink);

      // Extract task ID and file ID from response
      // Priority: task.id > task.file_id > file.id > id
      if (addResponse['task'] != null) {
        final task = addResponse['task'];
        taskId = task['id'] as String?;
        fileId = task['file_id'] as String?;
      }

      // Fallback to file.id or root id
      if (fileId == null || fileId.isEmpty) {
        if (addResponse['file'] != null) {
          fileId = addResponse['file']['id'] as String?;
        } else if (addResponse['id'] != null) {
          fileId = addResponse['id'] as String?;
        }
      }

      log('Initial IDs - Task: ${taskId ?? "none"}, File: ${fileId ?? "none"}');

      // If we have taskId but no fileId, poll task to get fileId
      if (taskId != null && (fileId == null || fileId.isEmpty)) {
        log('No file ID yet, polling task for file_id...');

        // Poll task for up to 5 seconds to get file_id
        final fileIdTimeout = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(fileIdTimeout)) {
          await Future.delayed(const Duration(seconds: 1));

          try {
            final taskData = await _api.getTaskStatus(taskId);
            final taskFileId = taskData['file_id'] as String?;
            if (taskFileId != null && taskFileId.isNotEmpty) {
              fileId = taskFileId;
              log('Got file ID from task: $fileId');
              break;
            }
          } catch (e) {
            log('Task status check failed: $e');
          }
        }
      }

      if (fileId == null || fileId.isEmpty) {
        log('Could not get file ID after polling');
        return null;
      }

      // Step 2: Task-based polling strategy (if taskId available)
      if (taskId != null) {
        log('Starting task-based polling for taskId: $taskId');

        // Quick check at 1 second
        await Future.delayed(_initialWait);

        try {
          final taskData = await _api.getTaskStatus(taskId);
          final taskPhase = taskData['phase'] as String?;
          final taskProgress = _parseProgress(taskData);

          log('Initial task check - phase: $taskPhase, progress: $taskProgress%');

          // Quick success - already complete
          if (taskPhase == 'PHASE_TYPE_COMPLETE') {
            log('Task complete on first check! Proceeding to file details...');
            return await _queryFileAndExtract(fileId, torrentName, log);
          }

          // Check if failed
          if (taskPhase == 'PHASE_TYPE_ERROR') {
            log('Task failed with error phase');
            await _cleanupFile(fileId, log);
            return null;
          }

          // Determine if worth waiting based on initial progress
          if (taskProgress >= _progressThreshold) {
            log('Good initial progress ($taskProgress%), likely cached - waiting for completion');
            return await _pollTaskUntilReady(taskId, fileId, torrentName, log);
          } else if (taskProgress >= 20) {
            log('Some progress ($taskProgress%), might be cached - checking progress delta');

            // Wait 2 seconds and check delta
            await Future.delayed(const Duration(seconds: 2));
            final taskData2 = await _api.getTaskStatus(taskId);
            final newProgress = _parseProgress(taskData2);
            final delta = newProgress - taskProgress;

            log('Progress after 2s: $newProgress% (delta: $delta)');

            if (delta >= _progressDeltaThreshold || newProgress >= _progressThreshold) {
              log('Good progress delta or threshold reached - waiting for completion');
              return await _pollTaskUntilReady(taskId, fileId, torrentName, log);
            }
          }

          // Low progress after 3 seconds total - check once more at 5 seconds
          await Future.delayed(const Duration(seconds: 2));
          final taskData3 = await _api.getTaskStatus(taskId);
          final finalProgress = _parseProgress(taskData3);

          if (finalProgress <= 0) {
            log('No progress after 5 seconds - torrent not cached');
            await _cleanupFile(fileId, log);
            return null;
          } else {
            log('Some progress detected ($finalProgress%), continuing with limited wait');
            return await _pollTaskUntilReady(taskId, fileId, torrentName, log, maxSeconds: 10);
          }

        } catch (e) {
          log('Task polling failed, falling back to file-based polling: $e');
          // Fall through to file-based polling
        }
      }

      // Step 3: Fallback to file-based polling if no task or task polling failed
      log('Using file-based polling for fileId: $fileId');

      // Wait 1 second before checking file
      await Future.delayed(_initialWait);

      Map<String, dynamic> fileData;
      try {
        fileData = await _api.getFileDetails(fileId);
      } catch (e) {
        log('Failed to get file details: $e');
        await _cleanupFile(fileId, log);
        return null;
      }

      final phase = fileData['phase'] as String?;
      final kind = fileData['kind'] as String?;
      log('Initial file check - phase: $phase, kind: $kind');

      // Quick success - already complete
      if (phase == 'PHASE_TYPE_COMPLETE') {
        return await _extractStreamingUrl(fileData, fileId, torrentName, log);
      }

      // Check if failed
      if (phase == 'PHASE_TYPE_ERROR') {
        log('Download failed with error phase');
        await _cleanupFile(fileId, log);
        return null;
      }

      // File-based progress monitoring (simplified since task polling is preferred)
      int lastProgress = _parseProgress(fileData);
      log('Initial file progress: $lastProgress%');

      if (lastProgress < _progressThreshold) {
        log('Low progress in file, not cached');
        await _cleanupFile(fileId, log);
        return null;
      }

      // Progress >= 50%, wait briefly for completion
      final stopTime = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(stopTime)) {
        await Future.delayed(_pollInterval);

        try {
          fileData = await _api.getFileDetails(fileId);
        } catch (e) {
          log('File poll failed: $e');
          continue;
        }

        final currentPhase = fileData['phase'] as String?;
        if (currentPhase == 'PHASE_TYPE_COMPLETE') {
          return await _extractStreamingUrl(fileData, fileId, torrentName, log);
        }

        if (currentPhase == 'PHASE_TYPE_ERROR') {
          log('Download entered error phase');
          await _cleanupFile(fileId, log);
          return null;
        }
      }

      log('Timed out waiting for file completion');
      await _cleanupFile(fileId, log);
      return null;

    } catch (e) {
      log('Error preparing torrent: $e');
      if (fileId != null && fileId.isNotEmpty) {
        await _cleanupFile(fileId, log);
      }
      return null;
    }
  }

  /// Poll task status until ready or timeout
  Future<Map<String, String>?> _pollTaskUntilReady(
    String taskId,
    String fileId,
    String torrentName,
    void Function(String) log,
    {int maxSeconds = 15}
  ) async {
    final stopTime = DateTime.now().add(Duration(seconds: maxSeconds));
    int lastProgress = 0;

    while (DateTime.now().isBefore(stopTime)) {
      await Future.delayed(_pollInterval);

      try {
        final taskData = await _api.getTaskStatus(taskId);
        final taskPhase = taskData['phase'] as String?;
        final taskProgress = _parseProgress(taskData);

        if (taskProgress != lastProgress) {
          log('Task progress: $taskProgress%, phase: $taskPhase');
          lastProgress = taskProgress;
        }

        // Check if complete
        if (taskPhase == 'PHASE_TYPE_COMPLETE') {
          log('Task completed! Querying file details...');
          return await _queryFileAndExtract(fileId, torrentName, log);
        }

        // Check if failed
        if (taskPhase == 'PHASE_TYPE_ERROR') {
          log('Task failed with error phase');
          await _cleanupFile(fileId, log);
          return null;
        }

        // If progress reaches 90%, we can try to query file
        if (taskProgress >= 90) {
          log('Task at 90%+, attempting to query file...');
          final result = await _queryFileAndExtract(fileId, torrentName, log);
          if (result != null) {
            return result;
          }
          // If file query failed, continue polling task
        }
      } catch (e) {
        log('Task poll error: $e');
        // Continue polling on error
      }
    }

    // Timeout - try one final file query
    log('Task polling timeout, attempting final file query...');
    final result = await _queryFileAndExtract(fileId, torrentName, log);
    if (result == null) {
      await _cleanupFile(fileId, log);
    }
    return result;
  }

  /// Query file details and extract streaming URL
  Future<Map<String, String>?> _queryFileAndExtract(
    String fileId,
    String torrentName,
    void Function(String) log,
  ) async {
    try {
      final fileData = await _api.getFileDetails(fileId);
      final phase = fileData['phase'] as String?;

      if (phase == 'PHASE_TYPE_COMPLETE') {
        return await _extractStreamingUrl(fileData, fileId, torrentName, log);
      } else {
        log('File not complete yet, phase: $phase');
        return null;
      }
    } catch (e) {
      log('Failed to query file details: $e');
      return null;
    }
  }

  /// Extract streaming URL from file data, handling folders
  Future<Map<String, String>?> _extractStreamingUrl(
    Map<String, dynamic> fileData,
    String fileId,
    String fallbackTitle,
    void Function(String) log,
  ) async {
    final kind = fileData['kind'] as String?;

    // Handle folder (torrent pack)
    if (kind == 'drive#folder') {
      log('Downloaded item is a folder, scanning for video files...');
      return await _findVideoInFolder(fileId, fallbackTitle, log);
    }

    // Direct file - get streaming URL
    final streamingUrl = _api.getStreamingUrl(fileData);
    if (streamingUrl == null || streamingUrl.isEmpty) {
      log('No streaming URL found in file data');
      return null;
    }

    final title = _extractTitle(fileData, fallbackTitle);
    log('Ready to stream: $title');

    return {
      'url': streamingUrl,
      'title': title,
    };
  }

  /// Find the best video file in a folder
  Future<Map<String, String>?> _findVideoInFolder(
    String folderId,
    String fallbackTitle,
    void Function(String) log,
  ) async {
    try {
      final result = await _api.listFiles(parentId: folderId);
      final files = result.files;

      log('Found ${files.length} files in folder');

      // Collect all video files with size >= threshold
      final videoFiles = <Map<String, dynamic>>[];

      for (final file in files) {
        final mimeType = (file['mime_type'] ?? '') as String;
        final name = (file['name'] ?? '') as String;
        final size = _parseSize(file['size']);
        final fileKind = file['kind'] as String?;

        // Recursively check subfolders
        if (fileKind == 'drive#folder') {
          final subResult = await _findVideoInFolder(
            file['id'] as String,
            fallbackTitle,
            log,
          );
          if (subResult != null) {
            return subResult;
          }
          continue;
        }

        final isVideo = mimeType.startsWith('video/') ||
            FileUtils.isVideoFile(name);

        if (isVideo && size >= _minVideoSizeBytes) {
          videoFiles.add(file);
          log('Found video: $name (${_formatSize(size)})');
        }
      }

      if (videoFiles.isEmpty) {
        log('No suitable video files found in folder');
        return null;
      }

      // Randomly select a video file from those that meet the size threshold
      final random = Random();
      final randomIndex = random.nextInt(videoFiles.length);
      final selectedFile = videoFiles[randomIndex];
      final selectedFileId = selectedFile['id'] as String;
      final selectedSize = _parseSize(selectedFile['size']);

      log('Randomly selected video ${randomIndex + 1} of ${videoFiles.length}: ${selectedFile['name']} (${_formatSize(selectedSize)})');

      // Fetch full file details to get streaming URL
      final fullFileData = await _api.getFileDetails(selectedFileId);
      final streamingUrl = _api.getStreamingUrl(fullFileData);

      if (streamingUrl == null || streamingUrl.isEmpty) {
        log('No streaming URL for selected video');
        return null;
      }

      final title = _extractTitle(fullFileData, fallbackTitle);

      return {
        'url': streamingUrl,
        'title': title,
      };
    } catch (e) {
      log('Error scanning folder: $e');
      return null;
    }
  }

  /// Clean up a file by moving it to trash
  Future<void> _cleanupFile(String fileId, void Function(String) log) async {
    try {
      log('Cleaning up file: $fileId');
      await _api.batchTrashFiles([fileId]);
      log('File moved to trash');
    } catch (e) {
      log('Failed to cleanup file: $e');
    }
  }

  /// Parse progress from file data
  int _parseProgress(Map<String, dynamic> fileData) {
    final progress = fileData['progress'];
    if (progress == null) return 0;
    if (progress is int) return progress;
    if (progress is double) return progress.round();
    if (progress is String) {
      return int.tryParse(progress) ?? 0;
    }
    return 0;
  }

  /// Parse size from file data
  int _parseSize(dynamic size) {
    if (size == null) return 0;
    if (size is int) return size;
    if (size is double) return size.round();
    if (size is String) {
      return int.tryParse(size) ?? 0;
    }
    return 0;
  }

  /// Format size for logging
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Extract title from file data
  String _extractTitle(Map<String, dynamic> fileData, String fallback) {
    final name = fileData['name'] as String?;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return fallback;
  }

  /// Check if PikPak is available (authenticated)
  Future<bool> isAvailable() async {
    return await _api.isAuthenticated();
  }
}
