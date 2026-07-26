import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml_events.dart';

/// Loads an XMLTV guide for one playlist: streams the (often multi-hundred-MB,
/// often gzipped) file to disk, parses it in an isolate with the streaming
/// event decoder — never `XmlDocument.parse`, the TV boxes have <2GB — and
/// keeps only the programmes that matter: channels whose tvg-id appears in
/// the playlist, inside a bounded time window. The surviving index is a few
/// MB at most and is snapshotted to disk so app restarts don't re-download
/// the guide.
///
/// Output rows are `[startMs, stopMs, title, description]` — deliberately
/// primitive so the same shape crosses the isolate boundary and serializes to
/// the cache file unchanged. IptvEpgService wraps them into EpgProgramme.
class XmltvEpgSource {
  XmltvEpgSource._();

  /// Re-download when the snapshot is older than this. Guide files typically
  /// update daily; half a day keeps evenings fresh without hammering hosts.
  static const _cacheTtl = Duration(hours: 12);

  /// Hard ceiling on the raw download.
  static const _maxDownloadBytes = 300 * 1024 * 1024;
  static const _downloadDeadline = Duration(minutes: 5);

  /// Programme window kept per channel: a little history for "what did I
  /// just miss", two days of future for the schedule view.
  static const _pastWindow = Duration(hours: 6);
  static const _futureWindow = Duration(hours: 48);
  static const _maxProgrammesPerChannel = 80;

  /// Ceiling on the whole index. A 10k-channel playlist against a full
  /// worldwide guide would otherwise build tens of MB of programme strings on
  /// a <2GB TV box; channels earlier in the guide win past this point.
  static const _maxTotalRows = 120000;
  static const _maxDescriptionChars = 400;

  /// Serializes loads per cache key so a double-tap can't download twice.
  static final Map<String, Future<Map<String, List<List<Object?>>>?>>
      _inFlight = {};

  /// Load (from snapshot or network) the guide for [epgUrl], filtered to
  /// [tvgIds]. Returns tvg-id → sorted `[startMs, stopMs, title, desc]` rows,
  /// or null when nothing could be loaded. Never throws.
  static Future<Map<String, List<List<Object?>>>?> load({
    required String epgUrl,
    required Set<String> tvgIds,
  }) {
    if (tvgIds.isEmpty) return Future.value(null);
    // In-flight coalescing keys on the exact request (URL + id set);
    // the disk snapshot below keys on the URL alone.
    final ids = tvgIds.toList()..sort();
    final key = md5.convert(utf8.encode('$epgUrl\n${ids.join(',')}')).toString();
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    final future = _load(epgUrl, tvgIds).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  static Future<Map<String, List<List<Object?>>>?> _load(
    String epgUrl,
    Set<String> tvgIds,
  ) async {
    // One snapshot per guide URL, overwritten in place — keying on the id
    // set too would mint a new multi-MB orphan on every channel-list churn
    // AND force a full guide re-download for a one-channel change. The
    // trade-off: channels added to the playlist since the snapshot was
    // written have no guide data until the next TTL refresh.
    final cacheFile = await _cacheFileFor(
      md5.convert(utf8.encode(epgUrl)).toString(),
    );
    _sweepCache(keep: cacheFile.path); // fire-and-forget housekeeping

    // Fresh snapshot → done, no network at all.
    final cached = await _readSnapshot(cacheFile);
    if (cached != null && !cached.isStale) return cached.index;

    // Download + parse. On any failure fall back to the stale snapshot —
    // yesterday's guide beats no guide.
    final index = await _downloadAndParse(epgUrl, tvgIds);
    if (index == null) {
      debugPrint('XmltvEpgSource: falling back to stale snapshot: $epgUrl');
      return cached?.index;
    }
    await _writeSnapshot(cacheFile, epgUrl, index);
    return index;
  }

  // ── Download ──────────────────────────────────────────────────────────────

  static Future<Map<String, List<List<Object?>>>?> _downloadAndParse(
    String epgUrl,
    Set<String> tvgIds,
  ) async {
    final client = http.Client();
    File? tempFile;
    try {
      final request = http.Request('GET', Uri.parse(epgUrl));
      request.headers['User-Agent'] = 'Debrify/1.0';
      request.headers['Accept'] = '*/*';
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        debugPrint('XmltvEpgSource: HTTP ${response.statusCode} for $epgUrl');
        return null;
      }
      final declared = response.contentLength;
      if (declared != null && declared > _maxDownloadBytes) {
        debugPrint('XmltvEpgSource: guide too large ($declared bytes)');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/xmltv_${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      final sink = tempFile.openWrite();
      var written = 0;
      final startedAt = DateTime.now();
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 60))) {
          written += chunk.length;
          if (written > _maxDownloadBytes ||
              DateTime.now().difference(startedAt) > _downloadDeadline) {
            debugPrint('XmltvEpgSource: download aborted (size/deadline)');
            return null;
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      // The heavy part runs off the UI isolate. Everything captured is
      // sendable (strings, ints, a set copy).
      final path = tempFile.path;
      final ids = Set<String>.of(tvgIds);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final index = await Isolate.run(() => parseXmltvFile(path, ids, nowMs));
      if (index.isEmpty) {
        debugPrint('XmltvEpgSource: no matching programmes in $epgUrl');
        return null;
      }
      debugPrint(
        'XmltvEpgSource: indexed ${index.length} channels from $epgUrl',
      );
      return index;
    } catch (e) {
      debugPrint('XmltvEpgSource: download/parse failed for $epgUrl: $e');
      return null;
    } finally {
      client.close();
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  // ── Parse (runs inside Isolate.run) ──────────────────────────────────────

  /// Stream-parse an XMLTV file, keeping `[startMs, stopMs, title, desc]`
  /// rows for channels in [tvgIds] within the time window around [nowMs].
  /// Exposed (not private) only because Isolate.run needs a callable that
  /// doesn't capture `this`; not part of the class's real API.
  @visibleForTesting
  static Future<Map<String, List<List<Object?>>>> parseXmltvFile(
    String path,
    Set<String> tvgIds,
    int nowMs,
  ) async {
    final file = File(path);
    final raf = await file.open();
    List<int> magic;
    try {
      magic = await raf.read(2);
    } finally {
      await raf.close();
    }
    final isGzip = magic.length == 2 && magic[0] == 0x1f && magic[1] == 0x8b;

    Stream<List<int>> bytes = file.openRead();
    if (isGzip) bytes = bytes.transform(gzip.decoder);

    final floorMs = nowMs - _pastWindow.inMilliseconds;
    final ceilMs = nowMs + _futureWindow.inMilliseconds;
    final index = <String, List<List<Object?>>>{};
    var totalRows = 0;

    // Streaming element state: the current <programme> and which of its
    // text-bearing children we're inside.
    String? channel;
    int? startMs;
    int? stopMs;
    StringBuffer? title;
    StringBuffer? desc;
    StringBuffer? textTarget;

    final events = bytes
        .transform(const Utf8Decoder(allowMalformed: true))
        .toXmlEvents();
    await for (final batch in events) {
      for (final event in batch) {
        if (event is XmlStartElementEvent) {
          switch (event.name) {
            case 'programme':
              String? ch, start, stop;
              for (final a in event.attributes) {
                switch (a.name) {
                  case 'channel':
                    ch = a.value;
                  case 'start':
                    start = a.value;
                  case 'stop':
                    stop = a.value;
                }
              }
              if (ch != null && tvgIds.contains(ch)) {
                channel = ch;
                startMs = _parseXmltvTime(start);
                stopMs = _parseXmltvTime(stop);
                title = StringBuffer();
                desc = StringBuffer();
              } else {
                channel = null;
              }
              // Self-closing <programme/> carries no children to await.
              if (event.isSelfClosing) channel = null;
            case 'title':
              if (channel != null && (title?.isEmpty ?? false)) {
                textTarget = event.isSelfClosing ? null : title;
              }
            case 'desc':
              if (channel != null && (desc?.isEmpty ?? false)) {
                textTarget = event.isSelfClosing ? null : desc;
              }
          }
        } else if (event is XmlTextEvent || event is XmlCDATAEvent) {
          final target = textTarget;
          if (target != null) {
            target.write(
              event is XmlTextEvent
                  ? event.value
                  : (event as XmlCDATAEvent).value,
            );
          }
        } else if (event is XmlEndElementEvent) {
          switch (event.name) {
            case 'title':
            case 'desc':
              textTarget = null;
            case 'programme':
              // `stop` is optional in the XMLTV DTD — some exporters rely on
              // the next programme's start. Keep those rows with a -1
              // placeholder (windowed on start alone) and fill the real stop
              // from the neighbour after sorting.
              final withinWindow = stopMs != null
                  ? (stopMs > startMs! && stopMs > floorMs && startMs < ceilMs)
                  : (startMs != null &&
                      startMs > floorMs &&
                      startMs < ceilMs);
              if (channel != null &&
                  startMs != null &&
                  withinWindow &&
                  // Only channels already indexed keep accepting rows once
                  // the total cap is hit, so no channel ends up half-empty.
                  (totalRows < _maxTotalRows || index.containsKey(channel))) {
                final t = title?.toString().trim() ?? '';
                if (t.isNotEmpty) {
                  var d = desc?.toString().trim() ?? '';
                  if (d.length > _maxDescriptionChars) {
                    d = '${d.substring(0, _maxDescriptionChars)}…';
                  }
                  (index[channel] ??= []).add([startMs, stopMs ?? -1, t, d]);
                  totalRows++;
                }
              }
              channel = null;
              textTarget = null;
          }
        }
      }
    }

    for (final entry in index.entries) {
      final rows = entry.value;
      rows.sort(
        (a, b) => (a[0]! as int).compareTo(b[0]! as int),
      );
      // Fill in stops the guide left implicit: a programme runs until the
      // next one starts (3h fallback for the channel's last entry).
      for (var i = 0; i < rows.length; i++) {
        if (rows[i][1] != -1) continue;
        final start = rows[i][0]! as int;
        final nextStart =
            i + 1 < rows.length ? rows[i + 1][0]! as int : null;
        rows[i][1] = (nextStart != null && nextStart > start)
            ? nextStart
            : start + const Duration(hours: 3).inMilliseconds;
      }
      if (rows.length > _maxProgrammesPerChannel) {
        rows.removeRange(_maxProgrammesPerChannel, rows.length);
      }
    }
    return index;
  }

  /// XMLTV time: `yyyyMMddHHmmss [±HHMM]`. Seconds and the offset are both
  /// optional in the wild; a missing offset means the publisher's local time,
  /// which we can only read as ours.
  static int? _parseXmltvTime(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*(?:([+-])(\d{2})(\d{2}))?',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final y = int.parse(match.group(1)!);
    final mo = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final h = int.parse(match.group(4)!);
    final mi = int.parse(match.group(5)!);
    final s = int.tryParse(match.group(6) ?? '') ?? 0;
    if (match.group(7) == null) {
      return DateTime(y, mo, d, h, mi, s).millisecondsSinceEpoch;
    }
    final offsetMinutes = (int.parse(match.group(8)!) * 60 +
            int.parse(match.group(9)!)) *
        (match.group(7) == '-' ? -1 : 1);
    return DateTime.utc(y, mo, d, h, mi, s)
        .subtract(Duration(minutes: offsetMinutes))
        .millisecondsSinceEpoch;
  }

  // ── Snapshot cache ────────────────────────────────────────────────────────

  /// Delete snapshots that no playlist has touched in a week — removed
  /// playlists and changed guide URLs would otherwise pile up multi-MB
  /// orphans forever on storage-starved TV boxes.
  static Future<void> _sweepCache({required String keep}) async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/epg_cache');
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      await for (final entity in dir.list()) {
        if (entity is! File || entity.path == keep) continue;
        try {
          if ((await entity.lastModified()).isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<File> _cacheFileFor(String cacheKey) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/epg_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$cacheKey.json');
  }

  static Future<_Snapshot?> _readSnapshot(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      // Snapshots can run to MBs for big playlists — decode off the UI
      // isolate past the same threshold the other services use.
      final decoded = raw.length > 100 * 1024
          ? await compute(jsonDecode, raw)
          : jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final fetchedAt = DateTime.tryParse(decoded['fetchedAt'] as String? ?? '');
      final channels = decoded['channels'];
      if (fetchedAt == null || channels is! Map<String, dynamic>) return null;
      final index = <String, List<List<Object?>>>{
        for (final entry in channels.entries)
          entry.key: [
            for (final row in (entry.value as List))
              [
                (row[0] as num).toInt(),
                (row[1] as num).toInt(),
                row[2] as String,
                row[3] as String,
              ],
          ],
      };
      return _Snapshot(index: index, fetchedAt: fetchedAt);
    } catch (e) {
      debugPrint('XmltvEpgSource: bad snapshot ${file.path}: $e');
      return null;
    }
  }

  static Future<void> _writeSnapshot(
    File file,
    String epgUrl,
    Map<String, List<List<Object?>>> index,
  ) async {
    try {
      // Encode off the UI isolate — the index can run to several MB, and the
      // read path already offloads its decode for the same reason.
      final encoded = await compute(jsonEncode, <String, dynamic>{
        'epgUrl': epgUrl,
        'fetchedAt': DateTime.now().toIso8601String(),
        'channels': index,
      });
      await file.writeAsString(encoded);
    } catch (e) {
      debugPrint('XmltvEpgSource: snapshot write failed: $e');
    }
  }
}

class _Snapshot {
  final Map<String, List<List<Object?>>> index;
  final DateTime fetchedAt;
  _Snapshot({required this.index, required this.fetchedAt});

  bool get isStale =>
      DateTime.now().difference(fetchedAt) >= XmltvEpgSource._cacheTtl;
}
