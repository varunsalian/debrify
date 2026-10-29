// Settings › Storage Usage: what Debrify keeps on this device, by kind, by
// profile and by file. Read-only apart from rescanning and copying the
// report for a bug report.
//
// Text is English like the rest of Settings: the app has no localization
// setup yet, so this page joins that migration when it exists.
import 'package:debrify/features/storage_usage/application/storage_usage_providers.dart';
import 'package:debrify/features/storage_usage/application/storage_usage_report.dart';
import 'package:debrify/features/storage_usage/models/storage_category_text.dart';
import 'package:debrify/features/storage_usage/models/storage_usage_models.dart';
import 'package:debrify/features/storage_usage/presentation/storage_usage_summary.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

const _title = 'Storage Usage';

class StorageUsagePage extends ConsumerStatefulWidget {
  const StorageUsagePage({super.key});

  @override
  ConsumerState<StorageUsagePage> createState() => _StorageUsagePageState();
}

class _StorageUsagePageState extends ConsumerState<StorageUsagePage> {
  /// The first row, focused once the report arrives when a remote or
  /// keyboard is driving focus, so Select works without a first DPAD press.
  final FocusNode _firstRow = FocusNode(debugLabel: 'storage-usage-first');
  bool _placedFocus = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(storageUsageProvider, (_, next) {
      if (next.hasValue) _placeInitialFocus();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _firstRow.dispose();
    super.dispose();
  }

  void _placeInitialFocus() {
    if (_placedFocus) return;
    _placedFocus = true;
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstRow.context != null) _firstRow.requestFocus();
    });
  }

  Future<void> _copyReport(StorageUsageReport report) async {
    await Clipboard.setData(
      ClipboardData(text: storageUsageReportText(report)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Storage report copied')));
  }

  Future<void> _explain(String title, String body) => showSettingsDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(storageUsageProvider);
    final report = usage.value;
    final Widget body;
    if (report != null) {
      body = _content(
        report,
        rescanning: usage.isLoading,
        // An error keeps the previous report: say it is not current.
        rescanFailed: usage.hasError && !usage.isLoading,
      );
    } else if (usage.hasError) {
      body = _centered(
        children: [
          const Text('Could not measure storage.'),
          const SizedBox(height: 12),
          FilledButton(
            autofocus: true,
            onPressed: ref.read(storageUsageProvider.notifier).rescan,
            child: const Text('Try again'),
          ),
        ],
      );
    } else {
      body = _centered(
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Measuring storage…'),
        ],
      );
    }
    return SettingsPageScaffold(title: _title, body: body);
  }

  Widget _centered({required List<Widget> children}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );

  Widget _content(
    StorageUsageReport report, {
    required bool rescanning,
    required bool rescanFailed,
  }) {
    final scan = report.scan;
    final categories = sortedStorageCategories(scan);
    var firstAssigned = false;
    FocusNode? first() {
      if (firstAssigned) return null;
      firstAssigned = true;
      return _firstRow;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsPageHeader(
                icon: Icons.storage_rounded,
                title: _title,
                subtitle:
                    'What Debrify keeps on this device, for every profile',
              ),
              const SizedBox(height: 20),
              StorageUsageSummary(report: report),
              const SizedBox(height: 20),
              if (categories.isNotEmpty) ...[
                SettingsSection(
                  title: 'What uses space',
                  children: [
                    for (final entry in categories)
                      SettingsTile(
                        focusNode: first(),
                        icon: _categoryIcon(entry.key),
                        title: entry.key.label,
                        subtitle: _share(entry.value, scan.totalBytes),
                        trailing: _size(entry.value),
                        onTap: () =>
                            _explain(entry.key.label, entry.key.explanation),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              if (report.profiles.isNotEmpty) ...[
                SettingsSection(
                  title: 'By profile',
                  blurb: 'Each profile keeps its own copy of its IPTV data.',
                  children: [
                    for (final profile in report.profiles)
                      SettingsTile(
                        focusNode: first(),
                        icon: profile.name == null && report.profilesKnown
                            ? Icons.person_off_outlined
                            : Icons.person_outline_rounded,
                        title: _profileTitle(report, profile),
                        subtitle: _profileSubtitle(report, profile),
                        trailing: _size(profile.total),
                        onTap: () => _explain(
                          _profileTitle(report, profile),
                          _profileExplanation(report, profile),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              if (scan.largest.isNotEmpty) ...[
                SettingsSection(
                  title: 'Largest files',
                  children: [
                    for (final file in scan.largest)
                      SettingsTile(
                        focusNode: first(),
                        icon: Icons.insert_drive_file_outlined,
                        title: p.basename(file.displayPath),
                        subtitle: _fileSubtitle(report, file),
                        trailing: _size(file.bytes),
                        onTap: () => _explain(
                          p.basename(file.displayPath),
                          '${file.category.label} · '
                          '${formatStorageBytes(file.bytes)}\n\n'
                          '${file.displayPath}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              SettingsSection(
                title: 'Report',
                children: [
                  SettingsTile(
                    focusNode: first(),
                    icon: Icons.refresh_rounded,
                    title: rescanning ? 'Scanning…' : 'Scan Again',
                    subtitle: rescanFailed
                        ? 'The last scan failed; these are older results'
                        : 'Measure every folder again',
                    // Stays focusable while scanning: disabling the focused
                    // row would throw a remote's focus off it.
                    onTap: () async {
                      if (rescanning) return;
                      ref.read(storageUsageProvider.notifier).rescan();
                    },
                  ),
                  SettingsTile(
                    icon: Icons.copy_rounded,
                    title: 'Copy Report',
                    subtitle: 'For a bug report; profile names are left out',
                    onTap: () => _copyReport(report),
                  ),
                ],
              ),
              if (scan.unreadableFolders > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${scan.unreadableFolders} folders could not be read and '
                  'are not counted.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Your device\'s own storage screen can show more: it also '
                'counts the app itself and space the system sets aside.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _size(int bytes) => Text(
    formatStorageBytes(bytes),
    style: const TextStyle(fontWeight: FontWeight.w700),
  );

  String _share(int bytes, int total) {
    if (total <= 0) return '0% of the total';
    final percent = bytes * 100 / total;
    return percent < 1
        ? 'Under 1% of the total'
        : '${percent.round()}% of the total';
  }

  String _profileTitle(StorageUsageReport report, StorageProfileUsage usage) =>
      usage.name ??
      (report.profilesKnown ? 'Deleted profile' : 'Profile ${usage.profileId}');

  String _profileSubtitle(
    StorageUsageReport report,
    StorageProfileUsage usage,
  ) {
    if (usage.name == null && report.profilesKnown) {
      return 'Leftover files from a removed profile';
    }
    if (usage.olderCopyBytes > 0) {
      return 'Includes ${formatStorageBytes(usage.olderCopyBytes)} of '
          'older copies';
    }
    return 'Current data';
  }

  String _profileExplanation(
    StorageUsageReport report,
    StorageProfileUsage usage,
  ) {
    final lines = <String>[
      'Current data: ${formatStorageBytes(usage.currentBytes)}',
      if (usage.olderCopyBytes > 0)
        'Older copies: ${formatStorageBytes(usage.olderCopyBytes)}. These '
            'are copies of the profile\'s data other than the one in use: '
            'kept for about a week after a restore, a reset or an import replaces '
            'them, or a new copy still being prepared.',
      if (usage.name == null && report.profilesKnown)
        'This profile no longer exists. Its files should have been removed '
            'with it.',
    ];
    return lines.join('\n\n');
  }

  String _fileSubtitle(StorageUsageReport report, StorageFile file) {
    final owner = file.profileId;
    if (owner == null) return file.category.label;
    final name = report.profiles
        .where((profile) => profile.profileId == owner)
        .map((profile) => profile.name)
        .firstOrNull;
    final who = name ?? (report.profilesKnown ? 'Deleted profile' : 'Profile');
    return '${file.category.label} · $who';
  }

  static IconData _categoryIcon(StorageCategory category) => switch (category) {
    StorageCategory.iptvCatalogs => Icons.live_tv_rounded,
    StorageCategory.debrifyTv => Icons.tv_rounded,
    StorageCategory.imageCache => Icons.image_outlined,
    StorageCategory.guideDownloads => Icons.downloading_rounded,
    StorageCategory.guideCache => Icons.calendar_view_day_rounded,
    StorageCategory.recordings => Icons.fiber_manual_record_outlined,
    StorageCategory.downloads => Icons.download_rounded,
    StorageCategory.logs => Icons.bug_report_outlined,
    StorageCategory.preferences => Icons.tune_rounded,
    StorageCategory.otherDatabases => Icons.dataset_outlined,
    StorageCategory.other => Icons.folder_outlined,
  };
}
