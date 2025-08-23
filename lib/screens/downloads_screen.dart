import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../services/download_service.dart';
import '../services/storage_service.dart';
import 'settings_screen.dart';
import '../services/android_native_downloader.dart';
import '../widgets/shimmer.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  late final StreamSubscription<TaskProgressUpdate> _progressSub;
  late final StreamSubscription<TaskStatusUpdate> _statusSub;
  StreamSubscription? _bytesSub;

  List<TaskRecord> _records = [];
  bool _loading = true;

  // Live progress snapshots keyed by taskId to show speed/ETA/sizes
  final Map<String, TaskProgressUpdate> _progressByTaskId = {};
  // Raw bytes and totals from Android native
  final Map<String, (int bytes, int? total)> _bytesByTaskId = {};
  // Move progress after completion (0..1, or failed)
  final Map<String, double> _moveProgressByTaskId = {};
  final Set<String> _moveFailed = {};

  String? _defaultUri;

  String _safReadable(String uri, String filename) {
    try {
      final decoded = Uri.decodeComponent(uri);
      final treeIndex = decoded.indexOf('tree/');
      if (treeIndex == -1) return 'Shared folder: $filename';
      String rest = decoded.substring(treeIndex + 5); // after 'tree/'
      // Expect formats like 'primary:Download/Subdir' or 'home:Documents'
      final colon = rest.indexOf(':');
      final path = colon != -1 ? rest.substring(colon + 1) : rest;
      if (path.isEmpty) return filename;
      return '$path/$filename';
    } catch (_) {
      return 'Shared folder: $filename';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    await DownloadService.instance.initialize();

    _progressSub = DownloadService.instance.progressStream.listen((update) {
      setState(() {
        _progressByTaskId[update.task.taskId] = update;
      });
    });

    _statusSub = DownloadService.instance.statusStream.listen((_) {
      _refresh();
    });

    _bytesSub = DownloadService.instance.bytesProgressStream.listen((evt) {
      setState(() {
        _bytesByTaskId[evt.taskId] = (evt.bytes, evt.total >= 0 ? evt.total : null);
      });
    }, onError: (_) {});

    DownloadService.instance.moveProgressStream.listen((move) {
      setState(() {
        if (move.failed) {
          _moveFailed.add(move.taskId);
          _moveProgressByTaskId.remove(move.taskId);
        } else if (move.done) {
          _moveProgressByTaskId[move.taskId] = 1.0;
        } else {
          _moveProgressByTaskId[move.taskId] = move.progress;
        }
      });
    });

    await _refresh();
  }

  Future<void> _refresh() async {
    final list = await DownloadService.instance.allRecords();
    if (!mounted) return;
    setState(() {
      _records = list;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _progressSub.cancel();
    _statusSub.cancel();
    _bytesSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureDefaultLocationOrRedirect() async {
    // No longer requiring a default location; always allow
    return;

    // Legacy callers expect an exception to stop flow; we now proceed
  }

  // Check if a URL is a download link by looking for file extensions
  bool _isDownloadLink(String url) {
    if (url.isEmpty) return false;
    
    // Common file extensions that indicate downloadable content
    final downloadExtensions = [
      '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v',
      '.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma',
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
      '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2',
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.svg',
      '.exe', '.dmg', '.pkg', '.deb', '.rpm', '.apk',
      '.iso', '.img', '.bin',
      '.txt', '.csv', '.json', '.xml', '.html', '.css', '.js',
      '.torrent', '.magnet'
    ];
    
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    
    final path = uri.path.toLowerCase();
    return downloadExtensions.any((ext) => path.endsWith(ext));
  }

  Future<void> _showAddDialog({String? initialUrl}) async {
    try {
      await _ensureDefaultLocationOrRedirect();
    } catch (_) {
      return;
    }

    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    if (initialUrl != null && initialUrl.isNotEmpty) {
      urlCtrl.text = initialUrl;
    }

    String? destPath;
    int? expectedSize;

    bool nameTouched = false;

    Future<void> recompute(StateSetter setLocal) async {
      final url = urlCtrl.text.trim();
      final manualName = nameCtrl.text.trim();

      if (url.isEmpty) {
        setLocal(() {
          destPath = null;
          expectedSize = null;
        });
        return;
      }

      String filename = manualName;
      if (!nameTouched) {
        try {
          final suggested = await DownloadTask(url: url)
              .withSuggestedFilename(unique: false);
          filename = suggested.filename;
          nameCtrl.text = filename;
        } catch (_) {
          final uri = Uri.tryParse(url);
          filename = (uri?.pathSegments.isNotEmpty ?? false)
              ? uri!.pathSegments.last
              : 'file';
          nameCtrl.text = filename;
        }
      } else if (filename.isEmpty) {
        final uri = Uri.tryParse(url);
        filename = (uri?.pathSegments.isNotEmpty ?? false)
            ? uri!.pathSegments.last
            : 'file';
      }

      // Destination preview: if Android SAF folder set, show a human-readable path
      String sanitize(String s) => s
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final dot = filename.lastIndexOf('.');
      final folder = sanitize(dot > 0 ? filename.substring(0, dot) : filename);
      if (Platform.isAndroid) {
        destPath = 'Download/Debrify/$filename';
      } else if (Platform.isMacOS) {
        try {
          final Directory? downloadsDir = await getDownloadsDirectory();
          if (downloadsDir != null) {
            destPath = 'Downloads/Debrify/$folder/$filename';
          } else {
            final docs = await getApplicationDocumentsDirectory();
            destPath = '${docs.path}/downloads/$folder/$filename';
          }
        } catch (e) {
          final docs = await getApplicationDocumentsDirectory();
          destPath = '${docs.path}/downloads/$folder/$filename';
        }
      } else {
        final docs = await getApplicationDocumentsDirectory();
        destPath = '${docs.path}/downloads/$folder/$filename';
      }

      try {
        expectedSize = await DownloadTask(url: url, filename: filename)
            .expectedFileSize();
      } catch (_) {
        expectedSize = null;
      }

      setLocal(() {});
    }

    String humanSize(int bytes) {
      const units = ['B', 'KB', 'MB', 'GB', 'TB'];
      double size = bytes.toDouble();
      int unit = 0;
      while (size >= 1024 && unit < units.length - 1) {
        size /= 1024;
        unit++;
      }
      return '${size.toStringAsFixed(2)} ${units[unit]}';
    }

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setLocal) {
          final kb = MediaQuery.of(context).viewInsets.bottom;
          // If we arrived with a prefilled URL, compute destination, filename and size once
          if ((initialUrl?.isNotEmpty ?? false) && destPath == null && urlCtrl.text.trim().isNotEmpty) {
            // schedule to avoid calling setState during build
            Future.microtask(() => recompute(setLocal));
          }
          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: kb),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.download_for_offline_rounded, color: Colors.white),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Add Download',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null && data!.text!.isNotEmpty) {
                                urlCtrl.text = data.text!;
                                await recompute(setLocal);
                              }
                            },
                            icon: const Icon(Icons.paste, color: Colors.white),
                            tooltip: 'Paste',
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Modern preview card
                    if (urlCtrl.text.trim().isNotEmpty || nameCtrl.text.trim().isNotEmpty)
                      _PreviewCard(
                        filename: nameCtrl.text.trim(),
                        host: Uri.tryParse(urlCtrl.text.trim())?.host ?? '',
                      ),
                    const SizedBox(height: 16),
                    _StyledField(
                      controller: urlCtrl,
                      label: 'Download URL',
                      hint: 'https://example.com/file',
                      icon: Icons.link,
                      onChanged: (_) => recompute(setLocal),
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: nameCtrl,
                      label: 'File name',
                      hint: 'movie.mp4',
                      icon: Icons.insert_drive_file,
                      onChanged: (_) {
                        nameTouched = true;
                        recompute(setLocal);
                      },
                    ),
                    if (destPath != null) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(Icons.folder, destPath!),
                          _chip(Icons.storage_rounded,
                              expectedSize != null ? humanSize(expectedSize!) : 'Unknown size'),
                          if (nameCtrl.text.contains('.'))
                            _chip(Icons.badge_rounded, nameCtrl.text.split('.').last.toUpperCase()),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFF334155)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (urlCtrl.text.trim().isEmpty)
                                ? null
                                : () => Navigator.of(context).pop(true),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Download'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        });
      },
    );

    if (res == true) {
      final url = urlCtrl.text.trim();
      final fileName = nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
      await DownloadService.instance.enqueueDownload(
        url: url,
        fileName: fileName,
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = _records
        .where((r) =>
            r.status == TaskStatus.enqueued ||
            r.status == TaskStatus.running ||
            r.status == TaskStatus.waitingToRetry ||
            r.status == TaskStatus.paused)
        .toList();
    final finished = _records
        .where((r) =>
            r.status == TaskStatus.complete ||
            r.status == TaskStatus.canceled ||
            r.status == TaskStatus.failed ||
            r.status == TaskStatus.notFound)
        .toList();

    return Column(
      children: [
        // Default-folder reminder removed
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(6),
            labelPadding: const EdgeInsets.symmetric(vertical: 10),
            overlayColor: MaterialStateProperty.all(Colors.transparent),
            indicator: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
            unselectedLabelColor: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
            tabs: const [
              Tab(text: 'In Progress'),
              Tab(text: 'Finished'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: 6,
                  itemBuilder: (context, index) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Shimmer(width: double.infinity, height: 16),
                        SizedBox(height: 8),
                        Shimmer(width: 160, height: 14),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _DownloadList(
                      records: inProgress,
                      onChanged: _refresh,
                      progressByTaskId: _progressByTaskId,
                      moveProgressByTaskId: _moveProgressByTaskId,
                      moveFailed: _moveFailed,
                      rawBytes: _bytesByTaskId,
                    ),
                    _DownloadList(
                      records: finished,
                      onChanged: _refresh,
                      progressByTaskId: _progressByTaskId,
                      moveProgressByTaskId: _moveProgressByTaskId,
                      moveFailed: _moveFailed,
                      rawBytes: _bytesByTaskId,
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.bottomRight,
            child: FloatingActionButton.extended(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              onPressed: () async {
                // Check clipboard for download links first
                final data = await Clipboard.getData('text/plain');
                String? clipboardUrl;
                
                if (data?.text != null && data!.text!.isNotEmpty) {
                  final url = data.text!.trim();
                  if (_isDownloadLink(url)) {
                    clipboardUrl = url;
                    // Show a brief message that a download link was found
                    if (mounted) {
                      final uri = Uri.tryParse(url);
                      final fileName = uri?.path.split('/').last ?? 'file';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Found download link in clipboard: $fileName'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                }
                
                // Show dialog with clipboard URL if it's a download link
                await _showAddDialog(initialUrl: clipboardUrl);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            child: Text(
              text,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// Styled input field widget for modern look
class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  const _StyledField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFF111827),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String filename;
  final String host;
  const _PreviewCard({super.key, required this.filename, required this.host});

  @override
  Widget build(BuildContext context) {
    if (filename.isEmpty && host.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x141E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (filename.isNotEmpty)
            Text(
              filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (host.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.public, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }
}

class _DownloadList extends StatelessWidget {
  final List<TaskRecord> records;
  final Future<void> Function() onChanged;
  final Map<String, TaskProgressUpdate> progressByTaskId;
  final Map<String, double> moveProgressByTaskId;
  final Set<String> moveFailed;
  final Map<String, (int bytes, int? total)> rawBytes;

  const _DownloadList({
    required this.records,
    required this.onChanged,
    required this.progressByTaskId,
    required this.moveProgressByTaskId,
    required this.moveFailed,
    required this.rawBytes,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(
        child: Text('No downloads'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => PressableScale(
        child: _DownloadTile(
          record: records[index],
          onChanged: onChanged,
          progress: progressByTaskId[records[index].task.taskId],
          moveProgress: moveProgressByTaskId[records[index].task.taskId],
          moveFailed: moveFailed.contains(records[index].task.taskId),
          rawBytes: rawBytes[records[index].task.taskId]?.$1,
          rawTotal: rawBytes[records[index].task.taskId]?.$2,
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final TaskRecord record;
  final TaskProgressUpdate? progress;
  final double? moveProgress; // 0..1 when moving to SAF
  final bool moveFailed;
  final Future<void> Function() onChanged;
  final int? rawBytes;
  final int? rawTotal;

  const _DownloadTile({
    required this.record,
    required this.onChanged,
    required this.progress,
    required this.moveProgress,
    required this.moveFailed,
    this.rawBytes,
    this.rawTotal,
  });

  String _statusText(TaskStatus status) {
    switch (status) {
      case TaskStatus.enqueued:
        return 'Queued';
      case TaskStatus.running:
        return 'Downloading';
      case TaskStatus.paused:
        return 'Paused';
      case TaskStatus.waitingToRetry:
        return 'Retrying';
      case TaskStatus.complete:
        return 'Completed';
      case TaskStatus.canceled:
        return 'Canceled';
      case TaskStatus.failed:
        return 'Failed';
      case TaskStatus.notFound:
        return 'Not found';
      default:
        return status.name;
    }
  }

  String _fmtBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    // Prefer live progress if available
    final double rawProgress = progress?.progress ?? (record.progress ?? 0.0);
    final name = record.task.filename;

    final int? totalBytes = rawTotal ?? (progress?.hasExpectedFileSize == true
        ? progress!.expectedFileSize
        : (record.expectedFileSize > 0 ? record.expectedFileSize : null));
    final bool isActive = record.status == TaskStatus.running ||
        record.status == TaskStatus.paused ||
        record.status == TaskStatus.enqueued ||
        record.status == TaskStatus.waitingToRetry;

    final double shownProgress = record.status == TaskStatus.complete
        ? 1.0
        : isActive
            ? (rawProgress.isNaN || rawProgress < 0.0)
                ? 0.0
                : rawProgress.clamp(0.0, 1.0)
            : 0.0;

    final int? downloadedBytes = rawBytes ?? ((totalBytes != null)
        ? (shownProgress * totalBytes).round()
        : null);
    final String? speedStr =
        progress?.hasNetworkSpeed == true ? progress!.networkSpeedAsString : null;
    final String? etaStr =
        progress?.hasTimeRemaining == true ? progress!.timeRemainingAsString : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    record.status == TaskStatus.complete && (moveProgress == null || moveProgress == 1.0)
                        ? Icons.check_circle
                        : Icons.download_rounded,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                          record.status == TaskStatus.complete
                              ? (moveFailed
                                  ? 'Move failed — kept in app storage'
                                  : (moveProgress != null && moveProgress! < 1.0
                                      ? 'Moving to selected folder…'
                                      : 'Completed'))
                              : _statusText(record.status),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: shownProgress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            if (record.status == TaskStatus.complete && !moveFailed && moveProgress != null && moveProgress! < 1.0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: moveProgress!.clamp(0.0, 1.0),
                minHeight: 6,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 4),
              Text('Moving ${(moveProgress! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
            ],
            const SizedBox(height: 10),
            // Rich stats row
            if (isActive)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (speedStr != null)
                    _StatChip(icon: Icons.speed, label: speedStr),
                  _StatChip(
                    icon: Icons.storage_rounded,
                    label: '${downloadedBytes != null ? _fmtBytes(downloadedBytes) : '—'} / '
                        '${totalBytes != null ? _fmtBytes(totalBytes) : '—'}',
                  ),
                  if (etaStr != null)
                    _StatChip(icon: Icons.timer, label: 'ETA $etaStr'),
                  if (speedStr == null &&
                      (downloadedBytes == null || totalBytes == null))
                    _StatChip(
                        icon: Icons.info_outline,
                        label: '${(shownProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            if (!isActive && record.status == TaskStatus.complete && totalBytes != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  _StatChip(
                    icon: Icons.storage_rounded,
                    label: _fmtBytes(totalBytes),
                  ),
                ],
              ),
            ],
            if (record.status == TaskStatus.complete)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final fileInfo = DownloadService.instance.getLastFileForTask(record.task.taskId);
                    if (fileInfo == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File not available to open yet')),
                      );
                      return;
                    }
                    final ok = await AndroidNativeDownloader.openContentUri(fileInfo.$1, fileInfo.$2);
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Opened Downloads instead')),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (record.task is DownloadTask && record.status == TaskStatus.running)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await DownloadService.instance.pause(record.task);
                      await onChanged();
                    },
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (record.task is DownloadTask && record.status == TaskStatus.paused)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await DownloadService.instance.resume(record.task);
                      await onChanged();
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                if (record.status == TaskStatus.enqueued ||
                    record.status == TaskStatus.running ||
                    record.status == TaskStatus.paused)
                  TextButton.icon(
                    onPressed: () async {
                      await DownloadService.instance.cancel(record.task);
                      await onChanged();
                    },
                    icon: const Icon(Icons.stop_circle, color: Colors.red),
                    label: const Text('Cancel',
                        style: TextStyle(color: Colors.red)),
                  ),
                const Spacer(),
                if (isActive)
                  Text('${(shownProgress * 100).toStringAsFixed(0)}%',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF475569).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
} 