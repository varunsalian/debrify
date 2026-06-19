import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/alldebrid_user.dart';
import '../models/alldebrid_file.dart';
import '../models/alldebrid_magnet.dart';
import '../models/alldebrid_link.dart';

/// Thrown when a magnet is added to AllDebrid but is not ready (not cached) yet.
/// AllDebrid has no cache-check endpoint, so the only way to know is to upload
/// the magnet and poll its status. Carries the magnetId so the caller can
/// decide whether to keep it (it will keep downloading on AllDebrid) or delete.
class AllDebridTorrentNotReadyException implements Exception {
  final String magnetId;
  final String apiKey;
  AllDebridTorrentNotReadyException(this.magnetId, this.apiKey);
  @override
  String toString() => 'File is not readily available in AllDebrid';
}

/// Result of adding a magnet and resolving its files on AllDebrid.
class AllDebridAddResult {
  final String magnetId;
  final String name;
  final List<AllDebridFile> files;
  AllDebridAddResult({
    required this.magnetId,
    required this.name,
    required this.files,
  });
}

class AllDebridService {
  static const String _baseUrl = 'https://api.alldebrid.com/v4';
  // magnet/status lives on the v4.1 endpoint (file/link info moved to
  // magnet/files in this version).
  static const String _statusUrl =
      'https://api.alldebrid.com/v4.1/magnet/status';

  /// AllDebrid status code for a magnet that has finished and is ready.
  static const int statusReady = 4;

  static Map<String, String> _authHeaders(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
      };

  /// Decodes an AllDebrid response envelope `{status, data}` / `{status, error}`.
  /// Returns the `data` map on success; throws with the API error message on
  /// failure.
  static Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> payload;
    try {
      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected response from AllDebrid');
      }
      payload = decoded;
    } catch (_) {
      throw Exception('AllDebrid returned an invalid response '
          '(HTTP ${response.statusCode})');
    }

    if (payload['status'] == 'success') {
      final data = payload['data'];
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    final error = payload['error'];
    final message = (error is Map && error['message'] != null)
        ? error['message'].toString()
        : 'AllDebrid request failed (HTTP ${response.statusCode})';
    throw Exception(message);
  }

  /// Fetches account info for [apiKey]. Throws on any failure.
  static Future<AllDebridUser> getUserInfo(String apiKey) async {
    try {
      debugPrint('AllDebridService: Requesting user info…');
      final response = await http
          .get(Uri.parse('$_baseUrl/user'), headers: _authHeaders(apiKey))
          .timeout(const Duration(seconds: 15));
      final data = _decode(response);
      final user = data['user'];
      if (user is! Map<String, dynamic>) {
        throw Exception('AllDebrid did not return user info');
      }
      debugPrint('AllDebridService: User info retrieved.');
      return AllDebridUser.fromJson(user);
    } catch (e) {
      debugPrint('AllDebridService: getUserInfo failed: $e');
      throw Exception('AllDebrid request failed: $e');
    }
  }

  /// Returns true when [apiKey] is valid.
  static Future<bool> validateApiKey(String apiKey) async {
    try {
      await getUserInfo(apiKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Uploads a magnet link (or bare infohash) to AllDebrid. Returns the magnet
  /// object: `{id, hash, name, size, ready}`. Throws on error.
  static Future<Map<String, dynamic>> uploadMagnet(
    String apiKey,
    String magnetOrHash,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/magnet/upload'),
            headers: _authHeaders(apiKey),
            body: {'magnets[]': magnetOrHash},
          )
          .timeout(const Duration(seconds: 30));
      final data = _decode(response);
      final magnets = data['magnets'];
      final first = magnets is List && magnets.isNotEmpty
          ? magnets.first
          : (magnets is Map<String, dynamic> ? magnets : null);
      if (first is! Map<String, dynamic>) {
        throw Exception('AllDebrid did not return a magnet id');
      }
      // A per-magnet error (e.g. invalid magnet) is reported inside the entry.
      if (first['error'] is Map) {
        final msg = (first['error'] as Map)['message']?.toString() ??
            'Invalid magnet';
        throw Exception(msg);
      }
      return first;
    } catch (e) {
      debugPrint('AllDebridService: uploadMagnet failed: $e');
      if (e is Exception) rethrow;
      throw Exception('AllDebrid magnet/upload failed: $e');
    }
  }

  /// Lists every magnet on the account (the AllDebrid "cloud" library).
  /// Calls `/v4.1/magnet/status` with no id, which returns all magnets.
  static Future<List<AllDebridMagnet>> listMagnets(String apiKey) async {
    final response = await http
        .post(
          Uri.parse(_statusUrl),
          headers: _authHeaders(apiKey),
          body: const <String, String>{},
        )
        .timeout(const Duration(seconds: 30));
    final data = _decode(response);
    final magnets = data['magnets'];
    final out = <AllDebridMagnet>[];
    if (magnets is List) {
      for (final m in magnets) {
        if (m is Map<String, dynamic>) {
          out.add(AllDebridMagnet.fromJson(m));
        }
      }
    } else if (magnets is Map<String, dynamic>) {
      // A single-magnet account can come back as one object.
      out.add(AllDebridMagnet.fromJson(magnets));
    }
    debugPrint('AllDebridService: listMagnets returned ${out.length} magnets');
    return out;
  }

  /// Fetches the status of a single magnet by [magnetId]. Returns the magnet
  /// status map (`{id, filename, size, status, statusCode, downloaded, …}`).
  static Future<Map<String, dynamic>> getMagnetStatus(
    String apiKey,
    String magnetId,
  ) async {
    final response = await http
        .post(
          Uri.parse(_statusUrl),
          headers: _authHeaders(apiKey),
          body: {'id': magnetId},
        )
        .timeout(const Duration(seconds: 20));
    final data = _decode(response);
    final magnets = data['magnets'];
    if (magnets is List && magnets.isNotEmpty) {
      final first = magnets.first;
      if (first is Map<String, dynamic>) return first;
    } else if (magnets is Map<String, dynamic>) {
      return magnets;
    }
    throw Exception('AllDebrid returned no status for magnet $magnetId');
  }

  /// Fetches and flattens every file inside the magnet [magnetId]. Each file
  /// carries a *locked* [AllDebridFile.link] that must be unlocked before use.
  static Future<List<AllDebridFile>> getMagnetFiles(
    String apiKey,
    String magnetId,
  ) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/magnet/files'),
          headers: _authHeaders(apiKey),
          body: {'id[]': magnetId},
        )
        .timeout(const Duration(seconds: 30));
    final data = _decode(response);
    final magnets = data['magnets'];
    List<dynamic>? entries;
    if (magnets is List && magnets.isNotEmpty) {
      final first = magnets.first;
      if (first is Map && first['files'] is List) {
        entries = first['files'] as List;
      }
    } else if (magnets is Map && magnets['files'] is List) {
      entries = magnets['files'] as List;
    }
    final files = <AllDebridFile>[];
    if (entries != null) {
      _flattenFiles(entries, '', files);
    }
    debugPrint('AllDebridService: magnet/files returned ${files.length} files');
    return files;
  }

  /// Recursively flattens AllDebrid's nested file tree. Each node is either a
  /// file (`{n, s, l}`) or a folder (`{n, e: [...]}`).
  static void _flattenFiles(
    List<dynamic> entries,
    String parentPath,
    List<AllDebridFile> out,
  ) {
    for (final entry in entries) {
      if (entry is! Map) continue;
      final name = entry['n']?.toString() ?? '';
      final path = parentPath.isEmpty ? name : '$parentPath/$name';
      final children = entry['e'];
      if (children is List) {
        _flattenFiles(children, path, out);
      } else {
        final link = entry['l']?.toString() ?? '';
        if (link.isEmpty) continue;
        out.add(AllDebridFile(
          path: path,
          size: _asInt(entry['s']),
          link: link,
        ));
      }
    }
  }

  /// Unlocks a locked link returned by [getMagnetFiles] into a ready-to-use
  /// direct download/stream URL. Throws on error.
  static Future<String> unlockLink(String apiKey, String link) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/link/unlock'),
          headers: _authHeaders(apiKey),
          body: {'link': link},
        )
        .timeout(const Duration(seconds: 30));
    final data = _decode(response);
    final url = data['link']?.toString() ?? '';
    if (url.isEmpty) {
      throw Exception('AllDebrid did not return a download link');
    }
    return url;
  }

  /// Lists the user's saved direct-download links (`/v4/user/links`). These are
  /// individual host links the user has saved (the "web downloads" library),
  /// distinct from magnets. Each [AllDebridLink.link] is locked and must be
  /// unlocked via [unlockLink] before use.
  static Future<List<AllDebridLink>> listSavedLinks(String apiKey) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/user/links'), headers: _authHeaders(apiKey))
        .timeout(const Duration(seconds: 30));
    final data = _decode(response);
    final links = data['links'];
    final out = <AllDebridLink>[];
    if (links is List) {
      for (final l in links) {
        if (l is Map<String, dynamic>) out.add(AllDebridLink.fromJson(l));
      }
    } else if (links is Map<String, dynamic>) {
      // Defensive: AllDebrid documents an array, but a map can arrive either as
      // a single link object ({link, filename, …}) or a keyed collection
      // ({"0": {…}, "1": {…}}). Disambiguate on the presence of a 'link' key.
      if (links.containsKey('link')) {
        out.add(AllDebridLink.fromJson(links));
      } else {
        for (final v in links.values) {
          if (v is Map<String, dynamic>) out.add(AllDebridLink.fromJson(v));
        }
      }
    }
    debugPrint('AllDebridService: listSavedLinks returned ${out.length} links');
    return out;
  }

  /// Saves [link] to the user's saved-links library (`/v4/user/links/save`).
  /// Throws on error.
  static Future<void> saveLink(String apiKey, String link) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/user/links/save'),
          headers: _authHeaders(apiKey),
          body: {'links[]': link},
        )
        .timeout(const Duration(seconds: 30));
    _decode(response);
  }

  /// Removes [link] from the user's saved-links library
  /// (`/v4/user/links/delete`). Throws on error.
  static Future<void> deleteSavedLink(String apiKey, String link) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/user/links/delete'),
          headers: _authHeaders(apiKey),
          body: {'links[]': link},
        )
        .timeout(const Duration(seconds: 20));
    _decode(response);
  }

  /// Deletes a magnet from the user's AllDebrid account. Best-effort.
  static Future<void> deleteMagnet(String apiKey, String magnetId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/magnet/delete'),
            headers: _authHeaders(apiKey),
            body: {'id': magnetId},
          )
          .timeout(const Duration(seconds: 20));
      _decode(response);
    } catch (e) {
      debugPrint('AllDebridService: deleteMagnet failed: $e');
    }
  }

  /// Adds [magnet] and resolves its (locked) files when it's cached.
  ///
  /// AllDebrid has no separate cache-check endpoint, but the upload response's
  /// `ready` flag IS an immediate, reliable cache indicator (verified live
  /// against the API): `true` = the content is already on AllDebrid's servers
  /// and instantly playable; `false` = not cached, so it would have to download
  /// from peers (minutes — not worth waiting on). So there is NO polling: a
  /// not-ready magnet throws [AllDebridTorrentNotReadyException] immediately,
  /// carrying the magnetId so the caller can delete it if it doesn't want the
  /// background download.
  static Future<AllDebridAddResult> addMagnetAndResolveFiles(
    String apiKey,
    String magnet,
  ) async {
    final uploaded = await uploadMagnet(apiKey, magnet);
    final magnetId = uploaded['id']?.toString() ?? '';
    final name = uploaded['name']?.toString() ?? '';
    if (magnetId.isEmpty) {
      throw Exception('AllDebrid did not return a magnet id');
    }

    if (uploaded['ready'] != true) {
      throw AllDebridTorrentNotReadyException(magnetId, apiKey);
    }

    final files = await getMagnetFiles(apiKey, magnetId);
    if (files.isEmpty) {
      throw AllDebridTorrentNotReadyException(magnetId, apiKey);
    }
    return AllDebridAddResult(
      magnetId: magnetId,
      name: name.isNotEmpty
          ? name
          : (files.isNotEmpty ? files.first.fileName : ''),
      files: files,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
