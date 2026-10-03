import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/utils/series_parser.dart';

class TorboxFileEntry {
  final TorboxFile file;
  final int index;
  final SeriesInfo seriesInfo;

  TorboxFileEntry({
    required this.file,
    required this.index,
    required this.seriesInfo,
  });
}
