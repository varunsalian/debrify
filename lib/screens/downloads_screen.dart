import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/download_service.dart';
import '../services/storage_service.dart';
import 'settings_screen.dart';

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

  List<TaskRecord> _records = [];
  bool _loading = true;

  // Live progress snapshots keyed by taskId to show speed/ETA/sizes
  final Map<String, TaskProgressUpdate> _progressByTaskId = {};

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

    _defaultUri = await StorageService.getDefaultDownloadUri();
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
    super.dispose();
  }

  Future<void> _ensureDefaultLocationOrRedirect() async {
    _defaultUri = await StorageService.getDefaultDownloadUri();
    if (_defaultUri != null && _defaultUri!.isNotEmpty) return;

    // Prompt to set default location
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set default download folder'),
        content: const Text(
            'Please choose a default download location in Settings before starting a download.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (go == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      _defaultUri = await StorageService.getDefaultDownloadUri();
      setState(() {});
    }

    throw Exception('default_location_missing');
  }

  Future<void> _showAddDialog() async {
    try {
      await _ensureDefaultLocationOrRedirect();
    } catch (_) {
      return;
    }

    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool wifiOnly = false;

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
      final defaultUri = _defaultUri;
      if (Platform.isAndroid && defaultUri != null && defaultUri.startsWith('content://')) {
        destPath = _safReadable(defaultUri, filename);
      } else {
        final docs = await getApplicationDocumentsDirectory();
        String sanitize(String s) => s
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final dot = filename.lastIndexOf('.');
        final folder = sanitize(dot > 0 ? filename.substring(0, dot) : filename);
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

    final res = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setLocal) {
          return Dialog(
            backgroundColor: const Color(0xFF1E293B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: LayoutBuilder(
              builder: (context, _) {
                final maxH = MediaQuery.of(context).size.height * 0.8;
                final kb = MediaQuery.of(context).viewInsets.bottom;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + kb),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF6366F1).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.add_rounded,
                                  color: Color(0xFF6366F1)),
                            ),
                            const SizedBox(width: 12),
                            const Text('Add Download',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: urlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Download URL',
                            hintText: 'https://... URL',
                            prefixIcon: Icon(Icons.link),
                          ),
                          onChanged: (_) => recompute(setLocal),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'File name',
                            hintText: 'example.mp4',
                            prefixIcon: Icon(Icons.insert_drive_file),
                          ),
                          onChanged: (_) {
                            nameTouched = true;
                            recompute(setLocal);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Switch(
                              value: wifiOnly,
                              onChanged: (v) => setLocal(() => wifiOnly = v),
                            ),
                            const Text('Wi‑Fi only'),
                            const Spacer(),
                          ],
                        ),
                        if (destPath != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Destination: $destPath',
                                    style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 6),
                                Text(
                                  'Size: '
                                  '${expectedSize != null ? humanSize(expectedSize!) : 'Unknown'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: (urlCtrl.text.trim().isEmpty)
                                    ? null
                                    : () => Navigator.of(context).pop(true),
                                child: const Text('Download'),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
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
        wifiOnly: wifiOnly,
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
        FutureBuilder<String?>(
          future: StorageService.getDefaultDownloadUri(),
          builder: (context, snap) {
            final missing = (snap.connectionState == ConnectionState.done) &&
                (snap.data == null || (snap.data?.isEmpty ?? true));
            if (!missing) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Set a default download folder in Settings to save files directly there.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                      setState(() {});
                    },
                    child: const Text('Open Settings'),
                  )
                ],
              ),
            );
          },
        ),
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
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
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'In Progress'),
              Tab(text: 'Finished'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _DownloadList(
                      records: inProgress,
                      onChanged: _refresh,
                      progressByTaskId: _progressByTaskId,
                    ),
                    _DownloadList(
                      records: finished,
                      onChanged: _refresh,
                      progressByTaskId: _progressByTaskId,
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.bottomRight,
            child: FloatingActionButton.extended(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        ),
      ],
    );
  }
}

class _DownloadList extends StatelessWidget {
  final List<TaskRecord> records;
  final Future<void> Function() onChanged;
  final Map<String, TaskProgressUpdate> progressByTaskId;

  const _DownloadList({
    required this.records,
    required this.onChanged,
    required this.progressByTaskId,
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
      itemBuilder: (context, index) => _DownloadTile(
        record: records[index],
        onChanged: onChanged,
        progress: progressByTaskId[records[index].task.taskId],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final TaskRecord record;
  final TaskProgressUpdate? progress;
  final Future<void> Function() onChanged;

  const _DownloadTile({
    required this.record,
    required this.onChanged,
    required this.progress,
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

    final int? totalBytes = progress?.hasExpectedFileSize == true
        ? progress!.expectedFileSize
        : null;
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

    final int? downloadedBytes = (totalBytes != null)
        ? (shownProgress * totalBytes).round()
        : null;
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
                    record.status == TaskStatus.complete
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
                      Text(_statusText(record.status),
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
                  if (downloadedBytes != null && totalBytes != null)
                    _StatChip(
                      icon: Icons.storage_rounded,
                      label:
                          '${_fmtBytes(downloadedBytes)} / ${_fmtBytes(totalBytes)}',
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
            if (record.status == TaskStatus.complete)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download completed')),
                    );
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Show'),
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
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8))),
              ],
            )
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