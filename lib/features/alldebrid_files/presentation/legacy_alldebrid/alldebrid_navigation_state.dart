import 'package:debrify/features/alldebrid_files/models/alldebrid_view.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_magnet.dart';

class AllDebridNavigationState {
  // Root view: torrents (magnets) vs saved links (web downloads).
  AllDebridView selectedView = AllDebridView.torrents;

  // When non-null, we are viewing this magnet's files.
  AllDebridMagnet? currentMagnet;

  List<AllDebridFile> currentFiles = [];

  bool loadingFiles = false;
}
