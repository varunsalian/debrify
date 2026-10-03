import 'package:debrify/models/debrid_download.dart';

class DebridDownloadState {
  final List<DebridDownload> downloads = [];

  bool isLoadingDownloads = false;

  bool isLoadingMoreDownloads = false;

  String downloadErrorMessage = '';

  int downloadPage = 1;

  bool hasMoreDownloads = true;
}
