import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../services/download_service.dart';
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
  Map<String, DownloadRecordDetails> _recordDetails = {};
  bool _loading = true;

  // Live progress snapshots keyed by taskId to show speed/ETA/sizes
  final Map<String, TaskProgressUpdate> _progressByTaskId = {};
  // Raw bytes and totals from Android native
  final Map<String, (int bytes, int? total)> _bytesByTaskId = {};
  // Move progress after completion (0..1, or failed)
  final Map<String, double> _moveProgressByTaskId = {};
  final Set<String> _moveFailed = {};
  final Set<String> _busyGroupIds = {};



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
    final details = DownloadService.instance.allRecordDetailsSnapshot();
    if (!mounted) return;
    setState(() {
      _records = list;
      _recordDetails = details;
      _loading = false;
    });
  }

  Future<void> _runGroupAction(String groupId, Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busyGroupIds.add(groupId);
    });
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyGroupIds.remove(groupId);
        });
      }
    }
  }

  Future<void> _pauseGroup(TorrentDownloadGroup group) async {
    final queuedIds = <String>[];
    final runningTasks = <Task>[];

    for (final item in group.items) {
      switch (item.record.status) {
        case TaskStatus.running:
          runningTasks.add(item.record.task);
          break;
        case TaskStatus.enqueued:
        case TaskStatus.waitingToRetry:
          queuedIds.add(item.record.task.taskId);
          break;
        default:
          break;
      }
    }

    if (queuedIds.isNotEmpty) {
      await DownloadService.instance.pauseQueuedTasksByIds(queuedIds);
    }

    for (final task in runningTasks) {
      await DownloadService.instance.pause(task);
    }
  }

  Future<void> _resumeGroup(TorrentDownloadGroup group) async {
    final queuedIds = <String>[];
    final tasksToResume = <Task>[];

    for (final item in group.items) {
      final status = item.record.status;
      final taskId = item.record.task.taskId;
      switch (status) {
        case TaskStatus.paused:
          if (DownloadService.instance.isPausedQueuedTask(taskId)) {
            queuedIds.add(taskId);
          } else {
            tasksToResume.add(item.record.task);
          }
          break;
        case TaskStatus.enqueued:
        case TaskStatus.waitingToRetry:
          if (DownloadService.instance.isPausedQueuedTask(taskId)) {
            queuedIds.add(taskId);
          } else {
            tasksToResume.add(item.record.task);
          }
          break;
        default:
          break;
      }
    }

    for (final task in tasksToResume) {
      await DownloadService.instance.resume(task);
    }

    if (queuedIds.isNotEmpty) {
      await DownloadService.instance.resumeQueuedTasksByIds(queuedIds);
    }
  }

  Future<void> _cancelGroup(TorrentDownloadGroup group) async {
    for (final item in group.items) {
      final status = item.record.status;
      if (status != TaskStatus.complete && status != TaskStatus.canceled) {
        await DownloadService.instance.cancel(item.record.task);
      }
    }
  }

  Future<void> _handleClearFinished(List<TorrentDownloadGroup> groups) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clear all finished?'),
            content: const Text('This removes completed entries from the list.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Clear All'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    for (final group in groups) {
      for (final item in group.items) {
        await DownloadService.instance.deleteRecord(item.record);
      }
    }
    await _refresh();
  }

  Future<void> _openGroupDetail(TorrentDownloadGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TorrentDownloadDetailScreen(
          groupId: group.id,
          groupTitle: group.title,
          initialGroup: group,
        ),
      ),
    );
    await _refresh();
  }

  Widget _buildFinishedTab(List<TorrentDownloadGroup> groups) {
    if (groups.isEmpty) {
      return const Center(child: Text('No downloads'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              const Text('Finished', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _busyGroupIds.isEmpty
                    ? () => _handleClearFinished(groups)
                    : null,
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('Clear All'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _TorrentGroupList(
            groups: groups,
            busyGroupIds: _busyGroupIds,
            isFinishedTab: true,
            onOpenGroup: _openGroupDetail,
          ),
        ),
      ],
    );
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
    final groups = buildTorrentGroups(
      records: _records,
      detailsByRecordId: _recordDetails,
      progressByTaskId: _progressByTaskId,
      rawBytes: _bytesByTaskId,
      moveProgressByTaskId: _moveProgressByTaskId,
      moveFailed: _moveFailed,
    );
    final inProgressGroups = groups.where((g) => !g.isFinished).toList();
    final finishedGroups = groups.where((g) => g.isFinished).toList();

    return Stack(
      children: [
        Column(
          children: [
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
            unselectedLabelColor:
                Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
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
                    key: ValueKey('download-shimmer-$index'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.3),
                      ),
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
                    _TorrentGroupList(
                      groups: inProgressGroups,
                      busyGroupIds: _busyGroupIds,
                      isFinishedTab: false,
                      onOpenGroup: _openGroupDetail,
                      onPauseAll: (group) =>
                          _runGroupAction(group.id, () => _pauseGroup(group)),
                      onResumeAll: (group) =>
                          _runGroupAction(group.id, () => _resumeGroup(group)),
                      onCancelAll: (group) =>
                          _runGroupAction(group.id, () => _cancelGroup(group)),
                    ),
                    _buildFinishedTab(finishedGroups),
                  ],
                ),
        ),
          ],
        ),
        Positioned(
          left: 16,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
          child: GestureDetector(
            onTap: () async {
              final data = await Clipboard.getData('text/plain');
              String? clipboardUrl;

              if (data?.text != null && data!.text!.isNotEmpty) {
                final url = data.text!.trim();
                if (_isDownloadLink(url)) {
                  clipboardUrl = url;
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

              await _showAddDialog(initialUrl: clipboardUrl);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    color: const Color(0xFF10B981),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Add',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
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
  const _PreviewCard({required this.filename, required this.host});

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

enum TorrentGroupState { moving, downloading, queued, paused, waiting, failed, canceled, completed }

extension TorrentGroupStateExt on TorrentGroupState {
  String get label {
    switch (this) {
      case TorrentGroupState.moving:
        return 'Moving';
      case TorrentGroupState.downloading:
        return 'Downloading';
      case TorrentGroupState.queued:
        return 'Queued';
      case TorrentGroupState.paused:
        return 'Paused';
      case TorrentGroupState.waiting:
        return 'Waiting';
      case TorrentGroupState.failed:
        return 'Needs attention';
      case TorrentGroupState.canceled:
        return 'Canceled';
      case TorrentGroupState.completed:
        return 'Completed';
    }
  }

  IconData get icon {
    switch (this) {
      case TorrentGroupState.moving:
        return Icons.folder_copy_rounded;
      case TorrentGroupState.downloading:
        return Icons.download_rounded;
      case TorrentGroupState.queued:
        return Icons.queue_rounded;
      case TorrentGroupState.paused:
        return Icons.pause_circle_rounded;
      case TorrentGroupState.waiting:
        return Icons.schedule_rounded;
      case TorrentGroupState.failed:
        return Icons.error_outline_rounded;
      case TorrentGroupState.canceled:
        return Icons.cancel_rounded;
      case TorrentGroupState.completed:
        return Icons.check_circle_rounded;
    }
  }

  int get sortPriority {
    switch (this) {
      case TorrentGroupState.moving:
        return 0;
      case TorrentGroupState.downloading:
        return 1;
      case TorrentGroupState.queued:
        return 2;
      case TorrentGroupState.paused:
        return 3;
      case TorrentGroupState.waiting:
        return 4;
      case TorrentGroupState.failed:
        return 5;
      case TorrentGroupState.canceled:
        return 6;
      case TorrentGroupState.completed:
        return 7;
    }
  }
}

class TorrentMeta {
  final String? torrentHash;
  final int? fileIndex;
  final String? restrictedLink;
  final String? apiKey;
  final bool isTorbox;
  final bool isTorboxZip;

  const TorrentMeta({
    this.torrentHash,
    this.fileIndex,
    this.restrictedLink,
    this.apiKey,
    this.isTorbox = false,
    this.isTorboxZip = false,
  });

  bool get hasHash => torrentHash != null && torrentHash!.isNotEmpty;

  /// TorBox CDN doesn't support HTTP Range for individual files, but ZIP downloads do.
  bool get isTorboxNonResumable => isTorbox && !isTorboxZip;
}

TorrentMeta parseTorrentMeta(String? meta) {
  if (meta == null || meta.isEmpty) return const TorrentMeta();
  try {
    final decoded = jsonDecode(meta);
    if (decoded is Map) {
      String? hash;
      int? fileIndex;
      String? restrictedLink;
      String? apiKey;
      bool isTorbox = false;
      bool isTorboxZip = false;

      final dynamic rawHash = decoded['torrentHash'];
      if (rawHash != null && rawHash.toString().isNotEmpty) {
        hash = rawHash.toString();
      }

      final dynamic rawIndex = decoded['fileIndex'];
      if (rawIndex is num) {
        fileIndex = rawIndex.toInt();
      } else if (rawIndex is String) {
        fileIndex = int.tryParse(rawIndex);
      }

      final dynamic rawRestricted = decoded['restrictedLink'];
      if (rawRestricted != null && rawRestricted.toString().isNotEmpty) {
        restrictedLink = rawRestricted.toString();
      }

      final dynamic rawApiKey = decoded['apiKey'];
      if (rawApiKey != null && rawApiKey.toString().isNotEmpty) {
        apiKey = rawApiKey.toString();
      }

      // Check if this is a TorBox download (regular or web download)
      if (decoded['torboxDownload'] == true || decoded['torboxWebDownload'] == true) {
        isTorbox = true;
        // ZIP downloads support HTTP Range requests
        if (decoded['torboxZip'] == true) {
          isTorboxZip = true;
        }
      }

      return TorrentMeta(
        torrentHash: hash,
        fileIndex: fileIndex,
        restrictedLink: restrictedLink,
        apiKey: apiKey,
        isTorbox: isTorbox,
        isTorboxZip: isTorboxZip,
      );
    }
  } catch (_) {}
  return const TorrentMeta();
}

class TorrentDownloadItem {
  final TaskRecord record;
  final DownloadRecordDetails? details;
  final TorrentMeta meta;

  const TorrentDownloadItem({
    required this.record,
    required this.details,
    required this.meta,
  });
}

class ActiveDownloadInfo {
  final String fileName;
  final String? eta;
  final String? speed;
  final bool hasQueued;

  const ActiveDownloadInfo({
    required this.fileName,
    this.eta,
    this.speed,
    this.hasQueued = false,
  });
}

class TorrentDownloadGroup {
  final String id;
  final String title;
  final String? torrentHash;
  final DateTime latestCreatedAt;
  final List<TorrentDownloadItem> items;
  final int totalFiles;
  final int completedFiles;
  final int runningFiles;
  final int queuedFiles;
  final int pausedFiles;
  final int waitingFiles;
  final int failedFiles;
  final int canceledFiles;
  final int notFoundFiles;
  final double progress;
  final int? totalBytes;
  final int? downloadedBytes;
  final double speedBytesPerSecond;
  final Duration? eta;
  final bool hasMoveInProgress;
  final bool hasMoveFailure;
  final TorrentGroupState state;
  final String statusLabel;
  final ActiveDownloadInfo? activeDownload;

  const TorrentDownloadGroup({
    required this.id,
    required this.title,
    required this.torrentHash,
    required this.latestCreatedAt,
    required this.items,
    required this.totalFiles,
    required this.completedFiles,
    required this.runningFiles,
    required this.queuedFiles,
    required this.pausedFiles,
    required this.waitingFiles,
    required this.failedFiles,
    required this.canceledFiles,
    required this.notFoundFiles,
    required this.progress,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.speedBytesPerSecond,
    required this.eta,
    required this.hasMoveInProgress,
    required this.hasMoveFailure,
    required this.state,
    required this.statusLabel,
    required this.activeDownload,
  });

  bool get isFinished =>
      state == TorrentGroupState.completed || state == TorrentGroupState.canceled;

  bool get hasIssues => failedFiles > 0 || hasMoveFailure || notFoundFiles > 0;

  bool get hasActive =>
      runningFiles > 0 || queuedFiles > 0 || pausedFiles > 0 || waitingFiles > 0 || hasMoveInProgress;

  /// TorBox CDN doesn't support HTTP Range for individual files, but ZIP downloads do.
  /// Returns true if ANY item in this group is a non-resumable TorBox download.
  bool get hasTorboxNonResumable => items.any((item) => item.meta.isTorboxNonResumable);
}

class _TorrentGroupBuilder {
  final String id;
  String title;
  bool titleIsFallback;
  String? torrentHash;
  DateTime latestCreatedAt;
  final List<TorrentDownloadItem> items = [];
  int totalFiles = 0;
  int completedFiles = 0;
  int runningFiles = 0;
  int queuedFiles = 0;
  int pausedFiles = 0;
  int waitingFiles = 0;
  int failedFiles = 0;
  int canceledFiles = 0;
  int notFoundFiles = 0;
  double totalBytes = 0;
  double downloadedBytes = 0;
  double fallbackProgressSum = 0;
  int fallbackProgressCount = 0;
  double speedBytesPerSecond = 0;
  bool hasMoveInProgress = false;
  bool hasMoveFailure = false;
  String? _firstRunningName;
  String? _firstRunningEta;
  String? _firstRunningSpeed;

  _TorrentGroupBuilder({
    required this.id,
    required this.title,
    required this.titleIsFallback,
    required this.torrentHash,
    required this.latestCreatedAt,
  });

  void add({
    required TaskRecord record,
    required DownloadRecordDetails? details,
    required TorrentMeta meta,
    required TaskProgressUpdate? progress,
    required (int bytes, int? total)? raw,
    required double? moveProgress,
    required bool moveFailed,
  }) {
    items.add(TorrentDownloadItem(record: record, details: details, meta: meta));
    totalFiles += 1;

    final created = record.task.creationTime;
    if (created.isAfter(latestCreatedAt)) {
      latestCreatedAt = created;
    }

    switch (record.status) {
      case TaskStatus.running:
        runningFiles += 1;
        if (_firstRunningName == null) {
          _firstRunningName = (details?.displayName?.trim().isNotEmpty ?? false)
              ? details!.displayName!.trim()
              : record.task.filename;
          if (progress != null && progress.hasTimeRemaining) {
            _firstRunningEta = formatEta(progress.timeRemaining);
          }
          if (progress != null && progress.hasNetworkSpeed) {
            _firstRunningSpeed = progress.networkSpeedAsString;
          }
        }
        break;
      case TaskStatus.enqueued:
        queuedFiles += 1;
        break;
      case TaskStatus.waitingToRetry:
        waitingFiles += 1;
        break;
      case TaskStatus.paused:
        pausedFiles += 1;
        break;
      case TaskStatus.complete:
        completedFiles += 1;
        break;
      case TaskStatus.canceled:
        canceledFiles += 1;
        break;
      case TaskStatus.failed:
        failedFiles += 1;
        break;
      case TaskStatus.notFound:
        notFoundFiles += 1;
        failedFiles += 1;
        break;
    }

    if (meta.hasHash && (torrentHash == null || torrentHash!.isEmpty)) {
      torrentHash = meta.torrentHash;
    }

    if (titleIsFallback) {
      final choice = _deriveTitle(record, details, meta);
      if (!choice.fallback) {
        title = choice.title;
        titleIsFallback = false;
      } else if (title.isEmpty && choice.title.isNotEmpty) {
        title = choice.title;
      }
    }

    if (moveProgress != null && moveProgress > 0 && moveProgress < 1) {
      hasMoveInProgress = true;
    }
    if (moveFailed) {
      hasMoveFailure = true;
    }

    final progressValue = _progressValue(record, progress);
    final int? total = raw?.$2 ?? _expectedTotalBytes(record, progress);
    int? downloaded = raw?.$1;
    if (downloaded == null && total != null && total > 0) {
      downloaded = (progressValue * total).clamp(0, total).round();
    } else if (downloaded == null && record.status == TaskStatus.complete && total != null && total > 0) {
      downloaded = total;
    }

    if (total != null && total > 0) {
      totalBytes += total;
      downloadedBytes += (downloaded ?? (record.status == TaskStatus.complete ? total : 0));
    } else {
      fallbackProgressSum += progressValue;
      fallbackProgressCount += 1;
    }

    if (progress != null && progress.hasNetworkSpeed && record.status == TaskStatus.running) {
      speedBytesPerSecond += progress.networkSpeed * 1024 * 1024;
    }
  }

  TorrentDownloadGroup build() {
    final int? totalBytesInt = totalBytes > 0 ? totalBytes.round() : null;
    final int? downloadedBytesInt = totalBytesInt != null
        ? downloadedBytes.clamp(0, totalBytes).round()
        : null;

    double effectiveProgress;
    if (totalBytesInt != null && totalBytesInt > 0) {
      effectiveProgress = (downloadedBytesInt ?? 0) / totalBytesInt;
    } else if (fallbackProgressCount > 0) {
      effectiveProgress = fallbackProgressSum / fallbackProgressCount;
    } else {
      effectiveProgress = 0.0;
    }
    effectiveProgress = effectiveProgress.clamp(0.0, 1.0);

    Duration? eta;
    if (speedBytesPerSecond > 0 && totalBytesInt != null && downloadedBytesInt != null) {
      final remaining = totalBytesInt - downloadedBytesInt;
      if (remaining > 0) {
        eta = Duration(seconds: (remaining / speedBytesPerSecond).round());
      }
    }

    final state = _deriveGroupState(
      hasMoveInProgress: hasMoveInProgress,
      running: runningFiles,
      queued: queuedFiles,
      paused: pausedFiles,
      waiting: waitingFiles,
      failed: failedFiles,
      canceled: canceledFiles,
      completed: completedFiles,
      total: totalFiles,
    );

    final label = _deriveStatusLabel(
      state,
      hasMoveFailure,
      failedFiles,
      pausedFiles,
      queuedFiles,
      waitingFiles,
    );

    final aggregatedEta = eta != null ? formatEta(eta) : null;
    final aggregatedSpeed = speedBytesPerSecond > 0 ? formatSpeed(speedBytesPerSecond) : null;
    ActiveDownloadInfo? activeDownload;
    if (_firstRunningName != null) {
      activeDownload = ActiveDownloadInfo(
        fileName: _firstRunningName!,
        eta: _firstRunningEta ?? aggregatedEta,
        speed: _firstRunningSpeed ?? aggregatedSpeed,
        hasQueued: (queuedFiles + waitingFiles) > 0,
      );
    }

    return TorrentDownloadGroup(
      id: id,
      title: title.isNotEmpty ? title : 'Download ${id.hashCode & 0xFFFF}',
      torrentHash: torrentHash,
      latestCreatedAt: latestCreatedAt,
      items: List.unmodifiable(items),
      totalFiles: totalFiles,
      completedFiles: completedFiles,
      runningFiles: runningFiles,
      queuedFiles: queuedFiles,
      pausedFiles: pausedFiles,
      waitingFiles: waitingFiles,
      failedFiles: failedFiles,
      canceledFiles: canceledFiles,
      notFoundFiles: notFoundFiles,
      progress: effectiveProgress,
      totalBytes: totalBytesInt,
      downloadedBytes: downloadedBytesInt,
      speedBytesPerSecond: speedBytesPerSecond,
      eta: eta,
      hasMoveInProgress: hasMoveInProgress,
      hasMoveFailure: hasMoveFailure,
      state: state,
      statusLabel: label,
      activeDownload: activeDownload,
    );
  }
}

class _TitleChoice {
  final String title;
  final bool fallback;
  const _TitleChoice(this.title, this.fallback);
}

_TitleChoice _deriveTitle(TaskRecord record, DownloadRecordDetails? details, TorrentMeta meta) {
  final torrentName = details?.torrentName?.trim();
  if (torrentName != null && torrentName.isNotEmpty) {
    return _TitleChoice(torrentName, false);
  }
  if (meta.torrentHash != null && meta.torrentHash!.isNotEmpty) {
    final hash = meta.torrentHash!;
    final shortHash = hash.length > 7 ? hash.substring(0, 7) : hash;
    return _TitleChoice('Torrent $shortHash', true);
  }
  final display = details?.displayName?.trim();
  if (display != null && display.isNotEmpty) {
    return _TitleChoice(display, true);
  }
  final filename = record.task.filename.trim();
  if (filename.isNotEmpty) {
    return _TitleChoice(filename, true);
  }
  return _TitleChoice('Download', true);
}

double _progressValue(TaskRecord record, TaskProgressUpdate? progress) {
  if (record.status == TaskStatus.complete) return 1.0;
  final double? live = progress?.progress;
  if (live != null && !live.isNaN && live >= 0) {
    return live.clamp(0.0, 1.0);
  }
  final double fallback = record.progress;
  if (!fallback.isNaN && fallback >= 0) {
    return fallback.clamp(0.0, 1.0);
  }
  return 0.0;
}

int? _expectedTotalBytes(TaskRecord record, TaskProgressUpdate? progress) {
  if (progress != null && progress.hasExpectedFileSize && progress.expectedFileSize > 0) {
    return progress.expectedFileSize;
  }
  if (record.expectedFileSize > 0) {
    return record.expectedFileSize;
  }
  return null;
}

TorrentGroupState _deriveGroupState({
  required bool hasMoveInProgress,
  required int running,
  required int queued,
  required int paused,
  required int waiting,
  required int failed,
  required int canceled,
  required int completed,
  required int total,
}) {
  if (hasMoveInProgress) return TorrentGroupState.moving;
  if (running > 0) return TorrentGroupState.downloading;
  if (queued > 0) return TorrentGroupState.queued;
  if (paused > 0) return TorrentGroupState.paused;
  if (waiting > 0) return TorrentGroupState.waiting;
  if (failed > 0) return TorrentGroupState.failed;
  if (canceled >= total && total > 0) return TorrentGroupState.canceled;
  if (completed >= total && total > 0) return TorrentGroupState.completed;
  return TorrentGroupState.waiting;
}

String _deriveStatusLabel(
  TorrentGroupState state,
  bool hasMoveFailure,
  int failed,
  int paused,
  int queued,
  int waiting,
) {
  if (hasMoveFailure) return 'Move failed';
  switch (state) {
    case TorrentGroupState.moving:
      return 'Moving to destination';
    case TorrentGroupState.downloading:
      return 'Downloading';
    case TorrentGroupState.queued:
      return queued > 1 ? '$queued in queue' : 'Queued';
    case TorrentGroupState.paused:
      return paused > 1 ? '$paused paused' : 'Paused';
    case TorrentGroupState.waiting:
      return waiting > 1 ? '$waiting waiting' : 'Waiting';
    case TorrentGroupState.failed:
      return failed > 1 ? '$failed failed' : 'Needs attention';
    case TorrentGroupState.canceled:
      return 'Canceled';
    case TorrentGroupState.completed:
      return 'Completed';
  }
}

List<TorrentDownloadGroup> buildTorrentGroups({
  required List<TaskRecord> records,
  required Map<String, DownloadRecordDetails> detailsByRecordId,
  required Map<String, TaskProgressUpdate> progressByTaskId,
  required Map<String, (int bytes, int? total)> rawBytes,
  required Map<String, double> moveProgressByTaskId,
  required Set<String> moveFailed,
}) {
  if (records.isEmpty) return const [];

  final Map<String, DownloadRecordDetails> detailsByTaskId = {};
  for (final entry in detailsByRecordId.entries) {
    detailsByTaskId[entry.key] = entry.value;
    final pluginId = entry.value.pluginTaskId;
    if (pluginId != null && pluginId.isNotEmpty) {
      detailsByTaskId[pluginId] = entry.value;
    }
  }

  final Map<String, _TorrentGroupBuilder> builders = {};

  for (final record in records) {
    final details = detailsByTaskId[record.task.taskId];
    final meta = parseTorrentMeta(details?.meta);
    final groupId = _deriveGroupId(record, details, meta);
    final builder = builders.putIfAbsent(groupId, () {
      final choice = _deriveTitle(record, details, meta);
      final created = details?.createdAt != null && details!.createdAt! > 0
          ? DateTime.fromMillisecondsSinceEpoch(details.createdAt!)
          : record.task.creationTime;
      return _TorrentGroupBuilder(
        id: groupId,
        title: choice.title,
        titleIsFallback: choice.fallback,
        torrentHash: meta.torrentHash,
        latestCreatedAt: created,
      );
    });

    builder.add(
      record: record,
      details: details,
      meta: meta,
      progress: progressByTaskId[record.task.taskId],
      raw: rawBytes[record.task.taskId],
      moveProgress: moveProgressByTaskId[record.task.taskId],
      moveFailed: moveFailed.contains(record.task.taskId),
    );
  }

  final groups = builders.values.map((b) => b.build()).toList();
  groups.sort((a, b) {
    final cmp = a.state.sortPriority.compareTo(b.state.sortPriority);
    if (cmp != 0) return cmp;
    return b.latestCreatedAt.compareTo(a.latestCreatedAt);
  });
  return groups;
}

String _deriveGroupId(TaskRecord record, DownloadRecordDetails? details, TorrentMeta meta) {
  if (meta.torrentHash != null && meta.torrentHash!.isNotEmpty) {
    return 'hash:${meta.torrentHash!.toLowerCase()}';
  }
  final torrentName = details?.torrentName;
  if (torrentName != null && torrentName.trim().isNotEmpty) {
    return 'name:${torrentName.trim().toLowerCase()}';
  }
  return 'task:${record.task.taskId}';
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final String value;
  if (unit == 0) {
    value = size.round().toString();
  } else if (size >= 10) {
    value = size.toStringAsFixed(1);
  } else {
    value = size.toStringAsFixed(2);
  }
  return '$value ${units[unit]}';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '-- MB/s';
  final megabytes = bytesPerSecond / (1024 * 1024);
  if (megabytes >= 1) {
    return '${megabytes.toStringAsFixed(megabytes >= 10 ? 1 : 2)} MB/s';
  }
  final kilobytes = bytesPerSecond / 1024;
  return '${kilobytes.toStringAsFixed(kilobytes >= 10 ? 1 : 2)} kB/s';
}

String formatEta(Duration? eta) {
  if (eta == null || eta.isNegative) return '--';
  if (eta.inHours >= 1) {
    final hours = eta.inHours;
    final minutes = eta.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }
  if (eta.inMinutes >= 1) {
    final minutes = eta.inMinutes;
    final seconds = eta.inSeconds.remainder(60);
    return '${minutes}m ${seconds}s';
  }
  return '${eta.inSeconds}s';
}

class _TorrentGroupList extends StatelessWidget {
  final List<TorrentDownloadGroup> groups;
  final Set<String> busyGroupIds;
  final bool isFinishedTab;
  final void Function(TorrentDownloadGroup) onOpenGroup;
  final Future<void> Function(TorrentDownloadGroup)? onPauseAll;
  final Future<void> Function(TorrentDownloadGroup)? onResumeAll;
  final Future<void> Function(TorrentDownloadGroup)? onCancelAll;

  const _TorrentGroupList({
    required this.groups,
    required this.busyGroupIds,
    required this.isFinishedTab,
    required this.onOpenGroup,
    this.onPauseAll,
    this.onResumeAll,
    this.onCancelAll,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Center(child: Text('No downloads'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = groups[index];
        final bool isBusy = busyGroupIds.contains(group.id);
        final bool isIOS = Platform.isIOS;

        // TorBox CDN doesn't support HTTP Range for individual files (but ZIP downloads do)
        final bool canPause = !isIOS && !isFinishedTab && !isBusy && !group.hasTorboxNonResumable && onPauseAll != null &&
            (group.runningFiles > 0 || group.queuedFiles > 0 || group.waitingFiles > 0);
        final bool canResume = !isIOS && !isFinishedTab && !isBusy && !group.hasTorboxNonResumable && onResumeAll != null &&
            group.pausedFiles > 0;
        final bool canCancel = !isBusy && onCancelAll != null &&
            (group.hasActive || group.failedFiles > 0 || group.notFoundFiles > 0);

        VoidCallback? pause = canPause ? () => onPauseAll!(group) : null;
        VoidCallback? resume = canResume ? () => onResumeAll!(group) : null;
        VoidCallback? cancel = canCancel ? () => onCancelAll!(group) : null;

        // Show info when TorBox group is active but pause is unavailable
        final bool showTorboxInfo = group.hasTorboxNonResumable &&
            !isFinishedTab &&
            !Platform.isIOS &&
            (group.runningFiles > 0 || group.queuedFiles > 0 || group.waitingFiles > 0);

        return PressableScale(
          onTap: () => onOpenGroup(group),
          child: _TorrentGroupCard(
            group: group,
            isBusy: isBusy,
            isFinished: isFinishedTab,
            onPauseAll: pause,
            onResumeAll: resume,
            onCancelAll: cancel,
            showTorboxPauseInfo: showTorboxInfo,
          ),
        );
      },
    );
  }
}

String _primaryStatusText(TorrentDownloadGroup group) {
  String base;
  switch (group.state) {
    case TorrentGroupState.moving:
      base = 'Finishing up';
      break;
    case TorrentGroupState.downloading:
      base = group.runningFiles > 1
          ? 'Downloading ${_countLabel(group.runningFiles, 'file')}'
          : 'Downloading';
      break;
    case TorrentGroupState.queued:
      base = 'In queue';
      break;
    case TorrentGroupState.paused:
      base = group.pausedFiles > 1
          ? 'Paused ${_countLabel(group.pausedFiles, 'file')}'
          : 'Paused';
      break;
    case TorrentGroupState.waiting:
      base = 'Waiting to retry';
      break;
    case TorrentGroupState.failed:
      base = 'Needs attention';
      break;
    case TorrentGroupState.canceled:
      base = 'Canceled';
      break;
    case TorrentGroupState.completed:
      base = 'Completed';
      break;
  }

  final suffix = <String>[];
  if (group.state != TorrentGroupState.downloading && group.runningFiles > 0) {
    suffix.add(_countLabel(group.runningFiles, 'downloading'));
  }
  if (group.state != TorrentGroupState.paused && group.pausedFiles > 0) {
    suffix.add(_countLabel(group.pausedFiles, 'paused'));
  }
  if (group.state != TorrentGroupState.queued && group.queuedFiles > 0) {
    suffix.add(_countLabel(group.queuedFiles, 'queued'));
  }
  if (group.state != TorrentGroupState.waiting && group.waitingFiles > 0) {
    suffix.add(_countLabel(group.waitingFiles, 'waiting'));
  }
  if (group.state != TorrentGroupState.failed && (group.failedFiles > 0 || group.notFoundFiles > 0 || group.hasMoveFailure)) {
    final issues = group.failedFiles + group.notFoundFiles;
    if (group.hasMoveFailure) {
      suffix.add('move retry');
    }
    if (issues > 0) {
      suffix.add(_countLabel(issues, 'issue'));
    }
  }
  if (group.hasMoveInProgress && group.state != TorrentGroupState.moving) {
    suffix.add('moving');
  }

  if (suffix.isNotEmpty) {
    base = '$base (${suffix.join(' • ')})';
  }
  return base;
}

String _bucketLine(TorrentDownloadGroup group) {
  final buckets = <String>[];
  buckets.add('${group.completedFiles}/${group.totalFiles} done');
  if (group.runningFiles > 0) {
    buckets.add(_countLabel(group.runningFiles, 'downloading'));
  }
  if (group.queuedFiles > 0) {
    buckets.add(_countLabel(group.queuedFiles, 'queued'));
  }
  if (group.pausedFiles > 0) {
    buckets.add(_countLabel(group.pausedFiles, 'paused'));
  }
  if (group.waitingFiles > 0) {
    buckets.add(_countLabel(group.waitingFiles, 'waiting'));
  }
  if (group.failedFiles > 0 || group.notFoundFiles > 0) {
    buckets.add(_countLabel(group.failedFiles + group.notFoundFiles, 'failed'));
  }
  return buckets.join(' • ');
}

String _countLabel(int count, String word) {
  final normalized = word.endsWith('s') ? word.substring(0, word.length - 1) : word;
  final plural = '${normalized}s';
  switch (normalized) {
    case 'issue':
      return count == 1 ? '1 issue' : '$count issues';
    case 'queued':
      return count == 1 ? '1 queued' : '$count queued';
    case 'paused':
      return count == 1 ? '1 paused' : '$count paused';
    case 'waiting':
      return count == 1 ? '1 waiting' : '$count waiting';
    case 'downloading':
      return count == 1 ? '1 downloading' : '$count downloading';
    default:
      return count == 1 ? '1 $normalized' : '$count $plural';
  }
}

String _activeMetrics(ActiveDownloadInfo info) {
  final parts = <String>[];
  if (info.eta != null && info.eta!.isNotEmpty && info.eta! != '--') {
    parts.add('≈ ${info.eta} left');
  }
  if (info.speed != null && info.speed!.isNotEmpty && info.speed! != '-- MB/s') {
    parts.add(info.speed!);
  }
  if (info.hasQueued) {
    parts.add('Next file starts afterward');
  }
  return parts.join(' • ');
}

class _TorrentGroupCard extends StatelessWidget {
  final TorrentDownloadGroup group;
  final bool isBusy;
  final bool isFinished;
  final VoidCallback? onPauseAll;
  final VoidCallback? onResumeAll;
  final VoidCallback? onCancelAll;
  final bool showTorboxPauseInfo;

  const _TorrentGroupCard({
    required this.group,
    required this.isBusy,
    required this.isFinished,
    this.onPauseAll,
    this.onResumeAll,
    this.onCancelAll,
    this.showTorboxPauseInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color stateColor = _groupStateColor(theme, group.state);
    final textTheme = theme.textTheme;

    final String primaryStatusText = _primaryStatusText(group);
    final String bucketLine = _bucketLine(group);
    final ActiveDownloadInfo? active = group.activeDownload;

    final chips = <Widget>[
      _InfoChip(
        icon: Icons.layers_rounded,
        label: '${group.totalFiles} files',
      ),
    ];

    if (group.downloadedBytes != null && group.totalBytes != null) {
      chips.add(
        _InfoChip(
          icon: Icons.data_usage_rounded,
          label: '${formatBytes(group.downloadedBytes!)} / ${formatBytes(group.totalBytes!)}',
        ),
      );
    } else if (group.totalBytes != null) {
      chips.add(
        _InfoChip(
          icon: Icons.data_usage_rounded,
          label: formatBytes(group.totalBytes!),
        ),
      );
    }

    if (group.speedBytesPerSecond > 0) {
      chips.add(
        _InfoChip(
          icon: Icons.speed_rounded,
          label: formatSpeed(group.speedBytesPerSecond),
        ),
      );
    }
    if (group.eta != null && !group.eta!.isNegative) {
      chips.add(
        _InfoChip(
          icon: Icons.timer_rounded,
          label: formatEta(group.eta),
        ),
      );
    }
    if (group.failedFiles > 0 || group.notFoundFiles > 0) {
      chips.add(
        _InfoChip(
          icon: Icons.error_outline_rounded,
          label: '${group.failedFiles + group.notFoundFiles} issues',
          foreground: theme.colorScheme.error,
          background: theme.colorScheme.error.withOpacity(0.12),
        ),
      );
    }
    if (group.hasMoveFailure) {
      chips.add(
        _InfoChip(
          icon: Icons.folder_off_rounded,
          label: 'Move failed',
          foreground: theme.colorScheme.error,
          background: theme.colorScheme.error.withOpacity(0.12),
        ),
      );
    }
    if (group.torrentHash != null && group.torrentHash!.isNotEmpty) {
      final hash = group.torrentHash!;
      final shortHash = hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;
      chips.add(
        _InfoChip(
          icon: Icons.tag_rounded,
          label: shortHash.toUpperCase(),
        ),
      );
    }

    final actions = <Widget>[];
    if (onPauseAll != null) {
      actions.add(
        TextButton.icon(
          onPressed: onPauseAll,
          icon: const Icon(Icons.pause_rounded),
          label: const Text('Pause'),
        ),
      );
    }
    if (onResumeAll != null) {
      actions.add(
        TextButton.icon(
          onPressed: onResumeAll,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Resume'),
        ),
      );
    }
    if (onCancelAll != null) {
      actions.add(
        TextButton.icon(
          onPressed: onCancelAll,
          icon: const Icon(Icons.delete_rounded),
          label: const Text('Cancel'),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: stateColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(group.state.icon, color: stateColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  primaryStatusText,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: stateColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (bucketLine.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    bucketLine,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (active != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Current: ${active.fileName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  if (_activeMetrics(active).isNotEmpty)
                                    Text(
                                      _activeMetrics(active),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          if (isBusy) ...[
                            const SizedBox(width: 12),
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: group.progress.isNaN ? 0 : group.progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation(stateColor),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: chips,
            ),
            if (actions.isNotEmpty || showTorboxPauseInfo) ...[
              const SizedBox(height: 16),
              if (showTorboxPauseInfo)
                Padding(
                  padding: EdgeInsets.only(bottom: actions.isNotEmpty ? 8 : 0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                      const SizedBox(width: 6),
                      Text(
                        'Pause unavailable for TorBox',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              if (actions.isNotEmpty)
                OverflowBar(
                  spacing: 12,
                  overflowSpacing: 12,
                  alignment: MainAxisAlignment.start,
                  children: actions,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? foreground;
  final Color? background;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.foreground,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color fg = foreground ?? theme.colorScheme.onSurfaceVariant;
    final Color bg = background ?? theme.colorScheme.surfaceVariant.withOpacity(0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

Color _groupStateColor(ThemeData theme, TorrentGroupState state) {
  switch (state) {
    case TorrentGroupState.moving:
      return theme.colorScheme.tertiary;
    case TorrentGroupState.downloading:
      return theme.colorScheme.primary;
    case TorrentGroupState.queued:
      return const Color(0xFFF59E0B);
    case TorrentGroupState.paused:
      return const Color(0xFF38BDF8);
    case TorrentGroupState.waiting:
      return const Color(0xFF22D3EE);
    case TorrentGroupState.failed:
      return theme.colorScheme.error;
    case TorrentGroupState.canceled:
      return theme.colorScheme.outline;
    case TorrentGroupState.completed:
      return const Color(0xFF22C55E);
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
  final bool isTorboxNonResumable;

  const _DownloadTile({
    required this.record,
    required this.onChanged,
    required this.progress,
    required this.moveProgress,
    required this.moveFailed,
    this.rawBytes,
    this.rawTotal,
    this.isTorboxNonResumable = false,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefer live progress if available
    final double rawProgress = progress?.progress ?? record.progress;
    final name = record.task.filename;

    final int? totalBytes = rawTotal ?? (() {
      if (progress?.hasExpectedFileSize == true) {
        return progress!.expectedFileSize;
      } else if (record.expectedFileSize > 0) {
        return record.expectedFileSize;
      } else {
        return null;
      }
    })();
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

    final int? downloadedBytes = rawBytes ?? (totalBytes != null
        ? (shownProgress * totalBytes).round()
        : null);
    final String? speedStr =
        progress?.hasNetworkSpeed == true ? progress!.networkSpeedAsString : null;
    final String? etaStr =
        progress?.hasTimeRemaining == true ? progress!.timeRemainingAsString : null;

    return Stack(
      children: [
        Card(
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
                    label:
                        '${downloadedBytes != null ? formatBytes(downloadedBytes) : '—'} / ${totalBytes != null ? formatBytes(totalBytes) : '—'}',
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
                    label: formatBytes(totalBytes),
                  ),
                ],
              ),
            ],
            if (record.status == TaskStatus.complete)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
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
                // TorBox CDN doesn't support HTTP Range for individual files (but ZIP downloads do)
                if (record.task is DownloadTask && record.status == TaskStatus.running && !Platform.isIOS && !isTorboxNonResumable)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await DownloadService.instance.pause(record.task);
                      await onChanged();
                    },
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (record.task is DownloadTask && record.status == TaskStatus.paused && !Platform.isIOS && !isTorboxNonResumable)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await DownloadService.instance.resume(record.task);
                      await onChanged();
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                if ((record.status == TaskStatus.enqueued ||
                    record.status == TaskStatus.running ||
                    record.status == TaskStatus.paused) &&
                    !(Platform.isIOS && record.status == TaskStatus.running))
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
                // Removed inline Clear button; handled by top-right X overlay
                if (isActive)
                  Text('${(shownProgress * 100).toStringAsFixed(0)}%',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ],
        ),
      ),
    ),
        if (!isActive)
          Positioned(
            right: 8,
            top: 8,
            child: InkResponse(
              onTap: () async {
                await DownloadService.instance.deleteRecord(record);
                await onChanged();
              },
              radius: 18,
              child: const Icon(
                Icons.close_rounded,
                color: Colors.red,
              ),
            ),
          ),
      ],
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

class TorrentDownloadDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupTitle;
  final TorrentDownloadGroup initialGroup;

  const TorrentDownloadDetailScreen({
    super.key,
    required this.groupId,
    required this.groupTitle,
    required this.initialGroup,
  });

  @override
  State<TorrentDownloadDetailScreen> createState() => _TorrentDownloadDetailScreenState();
}

class _TorrentDownloadDetailScreenState extends State<TorrentDownloadDetailScreen> {
  final Map<String, TaskProgressUpdate> _progressByTaskId = {};
  final Map<String, (int bytes, int? total)> _bytesByTaskId = {};
  final Map<String, double> _moveProgressByTaskId = {};
  final Set<String> _moveFailed = {};

  Map<String, DownloadRecordDetails> _recordDetails = {};
  List<TaskRecord> _records = [];
  TorrentDownloadGroup? _group;
  bool _loading = true;
  bool _busy = false;

  StreamSubscription<TaskProgressUpdate>? _progressSub;
  StreamSubscription<TaskStatusUpdate>? _statusSub;
  StreamSubscription? _bytesSub;
  StreamSubscription<MoveProgressUpdate>? _moveSub;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
    _init();
  }

  Future<void> _init() async {
    await DownloadService.instance.initialize();
    _progressSub = DownloadService.instance.progressStream.listen((update) {
      if (!mounted) return;
      setState(() {
        _progressByTaskId[update.task.taskId] = update;
      });
      _recomputeGroup();
    });
    _statusSub = DownloadService.instance.statusStream.listen((_) => _refresh());
    _bytesSub = DownloadService.instance.bytesProgressStream.listen((evt) {
      if (!mounted) return;
      setState(() {
        _bytesByTaskId[evt.taskId] = (evt.bytes, evt.total >= 0 ? evt.total : null);
      });
      _recomputeGroup();
    }, onError: (_) {});
    _moveSub = DownloadService.instance.moveProgressStream.listen((move) {
      if (!mounted) return;
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
      _recomputeGroup();
    });
    await _refresh();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _statusSub?.cancel();
    _bytesSub?.cancel();
    _moveSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await DownloadService.instance.allRecords();
    final details = DownloadService.instance.allRecordDetailsSnapshot();
    if (!mounted) return;
    setState(() {
      _records = list;
      _recordDetails = details;
      _loading = false;
    });
    _recomputeGroup();
  }

  void _recomputeGroup() {
    if (!mounted) return;
    final groups = buildTorrentGroups(
      records: _records,
      detailsByRecordId: _recordDetails,
      progressByTaskId: _progressByTaskId,
      rawBytes: _bytesByTaskId,
      moveProgressByTaskId: _moveProgressByTaskId,
      moveFailed: _moveFailed,
    );
    TorrentDownloadGroup? match;
    for (final group in groups) {
      if (group.id == widget.groupId) {
        match = group;
        break;
      }
    }
    setState(() {
      _group = match ?? _group;
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _pauseAll() async {
    final group = _group;
    if (group == null) return;
    final queuedIds = <String>[];
    final runningTasks = <Task>[];

    for (final item in group.items) {
      switch (item.record.status) {
        case TaskStatus.running:
          runningTasks.add(item.record.task);
          break;
        case TaskStatus.enqueued:
        case TaskStatus.waitingToRetry:
          queuedIds.add(item.record.task.taskId);
          break;
        default:
          break;
      }
    }

    if (queuedIds.isNotEmpty) {
      await DownloadService.instance.pauseQueuedTasksByIds(queuedIds);
    }

    for (final task in runningTasks) {
      await DownloadService.instance.pause(task);
    }
  }

  Future<void> _resumeAll() async {
    final group = _group;
    if (group == null) return;
    final queuedIds = <String>[];
    final tasksToResume = <Task>[];

    for (final item in group.items) {
      final status = item.record.status;
      final taskId = item.record.task.taskId;
      switch (status) {
        case TaskStatus.paused:
          if (DownloadService.instance.isPausedQueuedTask(taskId)) {
            queuedIds.add(taskId);
          } else {
            tasksToResume.add(item.record.task);
          }
          break;
        case TaskStatus.enqueued:
        case TaskStatus.waitingToRetry:
          if (DownloadService.instance.isPausedQueuedTask(taskId)) {
            queuedIds.add(taskId);
          } else {
            tasksToResume.add(item.record.task);
          }
          break;
        default:
          break;
      }
    }

    for (final task in tasksToResume) {
      await DownloadService.instance.resume(task);
    }

    if (queuedIds.isNotEmpty) {
      await DownloadService.instance.resumeQueuedTasksByIds(queuedIds);
    }
  }

  Future<void> _cancelAll() async {
    final group = _group;
    if (group == null) return;
    for (final item in group.items) {
      final status = item.record.status;
      if (status != TaskStatus.complete && status != TaskStatus.canceled) {
        await DownloadService.instance.cancel(item.record.task);
      }
    }
  }

  Widget _buildBody() {
    if (_loading && _group == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final group = _group;
    if (group == null) {
      return const Center(child: Text('Download group not found'));
    }

    final items = group.items;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isIOS = Platform.isIOS;
            return _TorrentGroupCard(
              group: group,
              isBusy: _busy,
              isFinished: group.isFinished,
              onPauseAll: (!isIOS && !group.isFinished &&
                      (group.runningFiles > 0 ||
                          group.queuedFiles > 0 ||
                          group.waitingFiles > 0))
                  ? () => _runAction(_pauseAll)
                  : null,
              onResumeAll: (!isIOS && !group.isFinished && group.pausedFiles > 0)
                  ? () => _runAction(_resumeAll)
                  : null,
              onCancelAll: (!group.isFinished &&
                      (group.hasActive || group.failedFiles > 0 || group.notFoundFiles > 0))
                  ? () => _runAction(_cancelAll)
                  : null,
            );
          }

          final item = items[index - 1];
          final taskId = item.record.task.taskId;
          return PressableScale(
            child: _DownloadTile(
              record: item.record,
              onChanged: _refresh,
              progress: _progressByTaskId[taskId],
              moveProgress: _moveProgressByTaskId[taskId],
              moveFailed: _moveFailed.contains(taskId),
              rawBytes: _bytesByTaskId[taskId]?.$1,
              rawTotal: _bytesByTaskId[taskId]?.$2,
              isTorboxNonResumable: item.meta.isTorboxNonResumable,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _group?.title ?? widget.groupTitle;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
