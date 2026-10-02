import 'package:debrify/models/playlist_entry.dart';

class LauncherEntry {
  final PlaylistEntry entry;
  final String resumeId;
  final int index;

  const LauncherEntry({
    required this.entry,
    required this.resumeId,
    required this.index,
  });
}
