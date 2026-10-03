import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/torbox_service.dart';

class TorboxStreamRequest {
  Future<String> requestTorboxStreamUrl({
    required String apiKey,
    required TorboxTorrent torrent,
    required TorboxFile file,
  }) async {
    final url = await TorboxService.requestFileDownloadLink(
      apiKey: apiKey,
      torrentId: torrent.id,
      fileId: file.id,
    );
    if (url.isEmpty) {
      throw Exception('Torbox returned an empty stream URL');
    }
    return url;
  }
}
