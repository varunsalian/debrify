import 'package:flutter/material.dart';
import '../../../models/playlist_entry.dart';
import '../../../utils/formatters.dart';

/// Multi-select pack picker: defaults to all files, shows their total size,
/// and returns selected entries in source order (or null on cancellation).
Future<List<PlaylistEntry>?> showSourceDownloadPicker(
  BuildContext context,
  List<PlaylistEntry> entries,
) {
  return showDialog<List<PlaylistEntry>>(
    context: context,
    builder: (dialogCtx) {
      final scheme = Theme.of(dialogCtx).colorScheme;
      final selected = {...entries}; // default: all selected
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final totalBytes = selected.fold<int>(
            0,
            (sum, e) => sum + (e.sizeBytes ?? 0),
          );
          final allOn = selected.length == entries.length;
          return AlertDialog(
            title: const Text('Download files'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setLocal(() {
                        if (allOn) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll(entries);
                        }
                      }),
                      child: Text(allOn ? 'None' : 'All'),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in entries)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: selected.contains(e),
                            title: Text(
                              e.title,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: Text(
                              (e.sizeBytes ?? 0) > 0
                                  ? Formatters.formatFileSize(e.sizeBytes!)
                                  : '',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            onChanged: (_) => setLocal(() {
                              if (selected.contains(e)) {
                                selected.remove(e);
                              } else {
                                selected.add(e);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(
                        dialogCtx,
                      ).pop(entries.where(selected.contains).toList()),
                child: Text(
                  totalBytes > 0
                      ? 'Download · ${Formatters.formatFileSize(totalBytes)}'
                      : 'Download',
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
