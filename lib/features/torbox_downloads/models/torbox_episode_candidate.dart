import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/utils/series_parser.dart';

class TorboxEpisodeCandidate {
  final TorboxFile file;
  final SeriesInfo info;
  final String displayName;

  TorboxEpisodeCandidate({
    required this.file,
    required this.info,
    required this.displayName,
  });

  int get size => file.size;
}
