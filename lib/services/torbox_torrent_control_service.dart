import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TorboxTorrentControlService {
  static const String _endpoint =
      'https://api.torbox.app/v1/api/torrents/controltorrent';

  static Future<void> deleteTorrent({
    required String apiKey,
    int? torrentId,
    bool deleteAll = false,
  }) async {
    final payload = <String, dynamic>{'operation': 'delete', 'all': deleteAll};
    if (torrentId != null) {
      payload['torrent_id'] = '$torrentId';
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': _formatAuthHeader(apiKey),
    };
    try {
      debugPrint(
        'TorboxTorrentControl: Deleting torrent $torrentId (all=$deleteAll)',
      );
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'TorboxTorrentControl: Delete failed (${response.statusCode}) body=${response.body}',
        );
        throw Exception('Failed to delete torrent (${response.statusCode})');
      }

      final Map<String, dynamic> body =
          json.decode(response.body) as Map<String, dynamic>;
      final bool success = body['success'] as bool? ?? false;
      if (!success) {
        final dynamic error = body['error'];
        throw Exception(error?.toString() ?? 'Torbox reported an error');
      }
    } catch (e) {
      debugPrint('TorboxTorrentControl: Exception while deleting: $e');
      rethrow;
    }
  }

  static String _formatAuthHeader(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return trimmed;
    }
    return 'Bearer $trimmed';
  }
}
