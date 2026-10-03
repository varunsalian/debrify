import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef TorboxFileListLayoutsDeps = ({
  BuildContext Function() context,
  Widget Function({
    required TorboxFileEntry entry,
    required bool isSelected,
    required VoidCallback onToggle,
    required int animationIndex,
    required Color surface,
    String? badge,
    String? subtitle,
    Future<void> Function()? onCopy,
  })
  buildTorboxFileCard,
});

class TorboxFileListLayouts {
  TorboxFileListLayouts(this._deps);
  final TorboxFileListLayoutsDeps _deps;

  Widget buildTorboxRawList({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  }) {
    // Hoisted out of itemBuilder: one theme lookup per list build, not per row.
    final app = AppThemeScope.of(_deps.context());
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      itemCount: entries.length,
      itemBuilder: (context, listIndex) {
        final entry = entries[listIndex];
        final isSelected = selectedIndices.contains(entry.index);
        final subtitle = entry.file.name != entry.file.shortName
            ? entry.file.name
            : entry.file.absolutePath;
        return Container(
          key: ValueKey('torbox-file-${entry.index}'),
          margin: const EdgeInsets.only(bottom: 12),
          child: _deps.buildTorboxFileCard(
            entry: entry,
            isSelected: isSelected,
            onToggle: () => onToggle(entry.index),
            animationIndex: listIndex,
            surface: app.cloud.dialogSurface,
            subtitle: subtitle,
            onCopy: onCopy == null ? null : () => onCopy(entry),
          ),
        );
      },
    );
  }

  Widget buildTorboxGenericList({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  }) {
    if (entries.isEmpty) {
      return buildEmptyFilesState();
    }

    final app = AppThemeScope.of(_deps.context());
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        buildSectionHeader('All Files'),
        const SizedBox(height: 12),
        for (int i = 0; i < entries.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: _deps.buildTorboxFileCard(
              entry: entries[i],
              isSelected: selectedIndices.contains(entries[i].index),
              onToggle: () => onToggle(entries[i].index),
              animationIndex: i,
              surface: app.cloud.dialogSurface,
              subtitle: entries[i].file.name != entries[i].file.shortName
                  ? entries[i].file.name
                  : entries[i].file.absolutePath,
              onCopy: onCopy == null ? null : () => onCopy(entries[i]),
            ),
          ),
      ],
    );
  }

  Widget buildTorboxMovieView({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  }) {
    final mainEntries = <TorboxFileEntry>[];
    final sampleEntries = <TorboxFileEntry>[];
    final extraEntries = <TorboxFileEntry>[];

    for (final entry in entries) {
      final fileNameLower = entry.file.shortName.toLowerCase();
      if (torboxFileLooksLikeVideo(entry.file)) {
        if (fileNameLower.contains('sample')) {
          sampleEntries.add(entry);
        } else {
          mainEntries.add(entry);
        }
      } else {
        extraEntries.add(entry);
      }
    }

    if (mainEntries.isEmpty && sampleEntries.isEmpty && extraEntries.isEmpty) {
      return buildEmptyFilesState();
    }

    final app = AppThemeScope.of(_deps.context());

    Widget buildSection(
      String title,
      List<TorboxFileEntry> sectionEntries, {
      String? badge,
    }) {
      if (sectionEntries.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader(title),
          const SizedBox(height: 12),
          for (int i = 0; i < sectionEntries.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: _deps.buildTorboxFileCard(
                entry: sectionEntries[i],
                isSelected: selectedIndices.contains(sectionEntries[i].index),
                onToggle: () => onToggle(sectionEntries[i].index),
                animationIndex: i,
                surface: app.cloud.dialogSurface,
                badge: badge,
                subtitle:
                    sectionEntries[i].file.name !=
                        sectionEntries[i].file.shortName
                    ? sectionEntries[i].file.name
                    : null,
                onCopy: onCopy == null ? null : () => onCopy(sectionEntries[i]),
              ),
            ),
          const SizedBox(height: 16),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        buildSection('Main', mainEntries, badge: 'Main'),
        buildSection('Sample', sampleEntries, badge: 'Sample'),
        buildSection('Extras', extraEntries, badge: 'Extra'),
      ],
    );
  }

  Widget buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget buildEmptyFilesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.folder_off_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No files available yet',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'We could not find any files for this torrent.',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
