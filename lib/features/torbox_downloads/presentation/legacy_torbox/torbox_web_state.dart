import 'package:debrify/models/torbox_web_download.dart';

class TorboxWebState {
  final List<TorboxWebDownload> webDownloads = [];

  bool isLoadingWebDownloads = false;

  bool isLoadingMoreWebDownloads = false;

  bool hasMoreWebDownloads = true;

  int webDownloadOffset = 0;

  String webDownloadErrorMessage = '';
}
