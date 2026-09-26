import 'package:flutter/material.dart';

enum LocalMoviePickMode { file, folder }

Future<LocalMoviePickMode?> showLocalMoviePickMode(
  BuildContext context, {
  required bool androidFolderSelection,
}) {
  return showModalBottomSheet<LocalMoviePickMode>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Local Movie Source',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose a video file or browse a folder.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
                _LocalPickTile(
                  autofocus: true,
                  icon: Icons.movie_creation_outlined,
                  color: const Color(0xFF34D399),
                  title: 'Pick Video File',
                  subtitle: 'Bind one local movie file',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(LocalMoviePickMode.file),
                ),
                const SizedBox(height: 8),
                _LocalPickTile(
                  icon: Icons.folder_open_rounded,
                  color: const Color(0xFF60A5FA),
                  title: 'Pick Folder',
                  subtitle: androidFolderSelection
                      ? 'Choose a movie file inside a folder'
                      : 'Match by filename, then use the largest match',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(LocalMoviePickMode.folder),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _LocalPickTile extends StatelessWidget {
  final bool autofocus;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LocalPickTile({
    this.autofocus = false,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      autofocus: autofocus,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: Colors.white.withValues(alpha: 0.05),
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    );
  }
}
