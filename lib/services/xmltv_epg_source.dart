import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml_events.dart';

import 'iptv_catalog_db.dart';
import 'iptv_load_phase.dart';

/// The filtered guide for one playlist: programmes per XMLTV channel id,
/// plus the name→id resolutions the parser made for channels that matched by
/// display-name rather than tvg-id (Kodi-style fallback — see
/// [XmltvEpgSource.normalizeChannelName]).
///
/// An instance with an empty [byId] means the guide downloaded and parsed
/// fine but matched nothing — a real answer, distinct from a null load
/// (download/parse failure).
class XmltvGuide {
  /// XMLTV channel id → sorted `[startMs, stopMs, title, desc]` rows.
  /// EMPTY in DB mode — the rows live in iptv_catalog.db under [guideKey]
  /// and never cross back to the UI heap.
  final Map<String, List<List<Object?>>> byId;

  /// Normalized display-name → XMLTV channel id, only for names the caller
  /// asked about. First guide channel carrying a name wins.
  final Map<String, String> nameToId;

  /// Whether any `<channel>` element paired with the playlist at all (by id
  /// or name). Distinguishes "the pairing works but no programmes survived
  /// the time window" from "ids and names genuinely don't line up" when
  /// nothing matched.
  final bool sawWantedChannel;

  /// DB mode: the epg_programmes key the rows were written under.
  final String? guideKey;

  /// Matched channel count. In legacy mode this mirrors byId.length; in DB
  /// mode it's the only place the number lives.
  final int channelCount;

  const XmltvGuide({
    required this.byId,
    required this.nameToId,
    this.sawWantedChannel = false,
    this.guideKey,
    int? channelCount,
  }) : channelCount = channelCount ?? byId.length;

  bool get isEmpty => channelCount == 0;
}

/// Loads an XMLTV guide for one playlist: streams the (often multi-hundred-MB,
/// often gzipped) file to disk, parses it in an isolate with the streaming
/// event decoder — never `XmlDocument.parse`, the TV boxes have <2GB — and
/// keeps only the programmes that matter: channels the playlist references by
/// tvg-id or by name, inside a bounded time window. The surviving index is a
/// few MB at most and is snapshotted to disk so app restarts don't
/// re-download the guide.
///
/// Output rows are `[startMs, stopMs, title, description]` — deliberately
/// primitive so the same shape crosses the isolate boundary and serializes to
/// the cache file unchanged. IptvEpgService wraps them into EpgProgramme.
class XmltvEpgSource {
  XmltvEpgSource._();

  /// Re-download when the snapshot is older than this. Guide files typically
  /// update daily; half a day keeps evenings fresh without hammering hosts.
  static const _cacheTtl = Duration(hours: 12);

  /// TTL for a snapshot of an empty (nothing-matched) result: long enough
  /// that a permanently mismatched pairing doesn't re-download a huge guide
  /// on every playlist open, short enough that a user mid-fixing their
  /// playlist/EPG pairing sees the fix land quickly.
  static const _emptyCacheTtl = Duration(minutes: 30);

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
  static final Map<String, Future<XmltvGuide?>> _inFlight = {};

  /// Last outright download/parse FAILURE per guide URL. Failures write no
  /// snapshot (only empty parses get the 30-min negative cache), and with
  /// guides now auto-derived for every Xtream login, a hanging or oversized
  /// xmltv.php would otherwise re-stream up to 300MB on every playlist
  /// open. In-memory on purpose — an app restart retries immediately.
  static final Map<String, DateTime> _lastFailureAt = {};
  static const _failureBackoff = Duration(minutes: 10);

  /// Kodi-style name matching key: lowercase with everything that isn't a
  /// letter or digit removed, so "BBC One HD" == "bbc-one_HD" == "BBC.One.HD".
  /// Unicode letters survive — plenty of guides publish non-Latin names.
  static String normalizeChannelName(String raw) =>
      raw.toLowerCase().replaceAll(_nonNameChars, '');
  static final _nonNameChars = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Load (from snapshot or network) the guide for [epgUrl], filtered to
  /// channels the playlist references by tvg-id ([tvgIds], matched
  /// case-insensitively — Kodi's default, and panels/guides really do
  /// disagree on casing) or by normalized name ([channelNames],
  /// pre-normalized via [normalizeChannelName]).
  /// Returns null only when nothing could be loaded at all. Never throws.
  static Future<XmltvGuide?> load({
    required String epgUrl,
    required Set<String> tvgIds,
    required Set<String> channelNames,
    String? dbPath,
    IptvLoadPhase? onPhase,
  }) {
    if (tvgIds.isEmpty && channelNames.isEmpty) return Future.value(null);
    // In-flight coalescing keys on the exact request (URL + id/name sets);
    // the stored guide below keys on the URL alone.
    final ids = tvgIds.toList()..sort();
    final names = channelNames.toList()..sort();
    // Chunked md5, never one giant joined string: at 50k ids + names the
    // joined key was a multi-MB transient String built on the UI isolate in
    // the page-open turn, just to name an in-flight map entry.
    final digestSink = _SingleDigestSink();
    final byteSink = md5.startChunkedConversion(digestSink);
    void addPart(String part) {
      byteSink.add(utf8.encode(part));
      byteSink.add(const [0x0A]);
    }

    addPart(epgUrl);
    ids.forEach(addPart);
    names.forEach(addPart);
    byteSink.close();
    final key = digestSink.value.toString();
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    final future =
        _load(epgUrl, tvgIds, channelNames, dbPath, onPhase).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  static Future<XmltvGuide?> _load(
    String epgUrl,
    Set<String> tvgIds,
    Set<String> channelNames,
    String? dbPath,
    IptvLoadPhase? onPhase,
  ) async {
    // One stored guide per URL, overwritten in place — keying on the id
    // set too would mint a new multi-MB orphan on every channel-list churn
    // AND force a full guide re-download for a one-channel change. The
    // trade-off: channels added to the playlist since the guide was
    // written have no data until the next TTL refresh.
    final guideKey = md5.convert(utf8.encode(epgUrl)).toString();
    final cacheFile = await _cacheFileFor(guideKey);
    _sweepCache(keep: cacheFile.path); // fire-and-forget housekeeping

    if (dbPath != null) {
      return _loadDbMode(epgUrl, tvgIds, channelNames, dbPath, guideKey,
          cacheFile, onPhase);
    }

    // Fresh snapshot → done, no network at all.
    final cached = await _readSnapshot(cacheFile);
    if (cached != null && !cached.isStale) return cached.guide;

    // A recent hard failure (hang, oversize, network) backs off rather than
    // re-attempting a potentially enormous download on every open.
    final lastFailure = _lastFailureAt[epgUrl];
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < _failureBackoff) {
      return cached?.guide;
    }

    // Download + parse. On any failure fall back to the stale snapshot —
    // yesterday's guide beats no guide.
    final guide = await _downloadAndParse(epgUrl, tvgIds, channelNames);
    if (guide == null) {
      _lastFailureAt[epgUrl] = DateTime.now();
      debugPrint('XmltvEpgSource: falling back to stale snapshot: $epgUrl');
      return cached?.guide;
    }
    _lastFailureAt.remove(epgUrl);
    if (guide.byId.isEmpty) {
      // Empty parse. A transient provider hiccup (guide mid-regeneration,
      // ids rotated for a day) must not erase a still-useful stale snapshot:
      // its 48h programme window outlives the 12h TTL by a lot.
      final fallback = cached?.guide;
      if (fallback != null && fallback.byId.isNotEmpty) {
        debugPrint('XmltvEpgSource: empty parse, keeping stale snapshot: '
            '$epgUrl');
        return fallback;
      }
      // No better answer exists — negative-cache the empty result briefly
      // (see _emptyCacheTtl) so a permanently mismatched pairing doesn't
      // re-download a multi-hundred-MB guide on every playlist open.
      await _writeSnapshot(cacheFile, epgUrl, guide);
      return guide;
    }
    await _writeSnapshot(cacheFile, epgUrl, guide);
    return guide;
  }

  /// DB mode: programme rows live in iptv_catalog.db, freshness in its
  /// epg_guides row, and the returned [XmltvGuide] is always light (empty
  /// byId + the guideKey to query under). Legacy JSON snapshots are imported
  /// once — preserving their original fetch time so a stale file doesn't
  /// masquerade as fresh — then deleted.
  /// Whether the legacy JSON guide file has nothing left to give and may be
  /// deleted: either its rows are now in the database, or it never held usable
  /// rows to begin with.
  ///
  /// A FAILED import must keep the file. The previous rule deleted it
  /// unconditionally ("imported or useless either way"), which is wrong for
  /// the throw case — a transient failure (a locked or full database) silently
  /// discarded a cached guide that can be hundreds of megabytes to fetch
  /// again, on exactly the low-end devices least able to re-download it. This
  /// is the one shipped-build data-loss path in the IPTV cleanup audit.
  ///
  /// [imported] is deliberately "the guide is readable from the database now",
  /// not "ingest returned without throwing", so a write that silently failed
  /// to land also keeps the file.
  @visibleForTesting
  static bool shouldDropLegacyGuideFile({
    required bool hadRows,
    required bool imported,
  }) => !hadRows || imported;

  static Future<XmltvGuide?> _loadDbMode(
    String epgUrl,
    Set<String> tvgIds,
    Set<String> channelNames,
    String dbPath,
    String guideKey,
    File legacyFile,
    IptvLoadPhase? onPhase,
  ) async {
    var info = IptvCatalogDb.epgGuideInfo(guideKey);

    // Set when this pass kept a legacy file whose import failed. That file is
    // then the ONLY copy of its guide, and the import is only ever attempted
    // while `info` is null — so nothing below may write guide metadata that
    // would make the next load skip the retry and strand it forever.
    var retainedLegacy = false;

    // One-time import of the legacy snapshot file.
    if (info == null && await legacyFile.exists()) {
      final cached = await _readSnapshot(legacyFile);
      final guide = cached?.guide;
      final hadRows = guide != null && guide.byId.isNotEmpty;
      if (hadRows) {
        try {
          final byId = guide.byId;
          final nameToId = guide.nameToId;
          final sawWanted = guide.sawWantedChannel;
          final fetchedAtMs = cached!.fetchedAt.millisecondsSinceEpoch;
          // Bulk programme-row import — same gate as every other whole-catalog
          // write.
          await IptvCatalogDb.runExclusive(
            () => Isolate.run(() => IptvCatalogDb.ingestEpgGuide(
                  dbPath: dbPath,
                  guideKey: guideKey,
                  epgUrl: epgUrl,
                  byId: byId,
                  nameToId: nameToId,
                  sawWanted: sawWanted,
                  fetchedAtMs: fetchedAtMs,
                )),
          );
          info = IptvCatalogDb.epgGuideInfo(guideKey);
        } catch (e) {
          debugPrint('XmltvEpgSource: legacy guide import failed: $e');
        }
      }
      if (shouldDropLegacyGuideFile(hadRows: hadRows, imported: info != null)) {
        try {
          await legacyFile.delete();
        } catch (_) {}
      } else {
        retainedLegacy = true;
      }
    }

    XmltvGuide? stored() {
      final snapshot = info;
      if (snapshot == null) return null;
      return XmltvGuide(
        byId: const {},
        nameToId: snapshot.nameToId,
        sawWantedChannel: snapshot.sawWanted,
        guideKey: guideKey,
        channelCount: snapshot.channelCount,
      );
    }

    bool freshEnough() {
      final snapshot = info;
      if (snapshot == null) return false;
      final ttl = snapshot.channelCount == 0 ? _emptyCacheTtl : _cacheTtl;
      return DateTime.now().millisecondsSinceEpoch - snapshot.fetchedAt <
          ttl.inMilliseconds;
    }

    if (freshEnough()) return stored();

    final lastFailure = _lastFailureAt[epgUrl];
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < _failureBackoff) {
      return stored();
    }

    final guide = await _downloadAndParse(
      epgUrl,
      tvgIds,
      channelNames,
      dbPath: dbPath,
      guideKey: guideKey,
      onPhase: onPhase,
    );
    if (guide == null) {
      _lastFailureAt[epgUrl] = DateTime.now();
      debugPrint('XmltvEpgSource: falling back to stored guide: $epgUrl');
      return stored();
    }
    _lastFailureAt.remove(epgUrl);
    if (guide.isEmpty) {
      // Empty parse: existing rows (they outlive their TTL usefully) win;
      // the parser deliberately wrote nothing, so they're intact.
      final fallback = stored();
      if (fallback != null && fallback.channelCount > 0) {
        debugPrint(
            'XmltvEpgSource: empty parse, keeping stored guide: $epgUrl');
        return fallback;
      }
      if (!retainedLegacy) {
        IptvCatalogDb.markEpgGuideEmpty(
          guideKey: guideKey,
          epgUrl: epgUrl,
          sawWanted: guide.sawWantedChannel,
        );
      }
      // With a retained file, the negative cache is deliberately NOT written:
      // its row would satisfy `info != null` on the next load, skip the legacy
      // import, and leave a guide sitting on disk that can never be read
      // again. Leaving the metadata absent costs one re-parse and keeps the
      // retry alive.
      return guide;
    }
    // The parser ingested + stamped inside its isolate; the guide is light.
    // A retained legacy file is now genuinely obsolete — the database holds a
    // newer copy — so it stops being an orphan nothing would ever delete.
    if (retainedLegacy) {
      try {
        await legacyFile.delete();
      } catch (_) {}
    }
    return guide;
  }

  // ── Download ──────────────────────────────────────────────────────────────

  static Future<XmltvGuide?> _downloadAndParse(
    String epgUrl,
    Set<String> tvgIds,
    Set<String> channelNames, {
    String? dbPath,
    String? guideKey,
    IptvLoadPhase? onPhase,
  }) async {
    final client = http.Client();
    File? tempFile;
    try {
      final request = http.Request('GET', Uri.parse(epgUrl));
      // Known-player UA: panel xmltv.php endpoints sit behind the same WAFs
      // as player_api and challenge unknown agents (see IptvEpgService).
      request.headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18';
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
          // Already a streaming loop with a running total — the guide is the
          // longest single download in the whole IPTV flow, so this is the one
          // place a genuinely live number is free.
          onPhase?.call(
            IptvLoadPhases.downloading,
            bytes: written,
            totalBytes: declared,
          );
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
      // sendable (strings, ints, set copies). In DB mode the isolate ALSO
      // writes the finished index into iptv_catalog.db itself — the rows die
      // with the isolate instead of crossing back to this heap.
      final path = tempFile.path;
      final ids = Set<String>.of(tvgIds);
      final names = Set<String>.of(channelNames);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final capturedDbPath = dbPath;
      final capturedGuideKey = guideKey;
      final capturedUrl = epgUrl;
      // The download is already done; what remains is a large parse that, in
      // DB mode, writes the programme rows into iptv_catalog.db. That is
      // whole-catalog-scale write work, so it takes the shared maintenance
      // gate rather than contending with a migration, adoption or ingest.
      // (The gate is deliberately taken HERE and not around the fetch above —
      // a guide download can take minutes.)
      final guide = await IptvCatalogDb.runExclusive(
        () => Isolate.run(() => parseXmltvFile(
              path,
              ids,
              names,
              nowMs,
              dbPath: capturedDbPath,
              guideKey: capturedGuideKey,
              epgUrl: capturedUrl,
            )),
      );
      if (guide.isEmpty) {
        // Parsed fine, matched nothing — a real answer (the caller tells the
        // user WHY there's no guide), distinct from a null failure.
        debugPrint('XmltvEpgSource: no matching programmes in $epgUrl');
      } else {
        debugPrint(
          'XmltvEpgSource: indexed ${guide.channelCount} channels from '
          '$epgUrl${guide.guideKey != null ? ' (to catalog DB)' : ''}',
        );
      }
      return guide;
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
  /// rows for matched channels within the time window around [nowMs]. A
  /// channel matches by id (in [tvgIds]) or by any of its `<display-name>`s
  /// normalizing into [wantedNames] — the Kodi-style fallback chain, resolved
  /// here because `<channel>` elements precede `<programme>`s in XMLTV.
  ///
  /// Ids are canonicalized to LOWERCASE on both sides — the index's keys,
  /// the name→id map's values, and every membership test — because playlist
  /// tvg-ids and guide channel ids routinely disagree only in case (Kodi
  /// matches ids case-insensitively by default for the same reason).
  /// Exposed (not private) only because Isolate.run needs a callable that
  /// doesn't capture `this`; not part of the class's real API.
  @visibleForTesting
  static Future<XmltvGuide> parseXmltvFile(
    String path,
    Set<String> tvgIds,
    Set<String> wantedNames,
    int nowMs, {
    String? dbPath,
    String? guideKey,
    String? epgUrl,
  }) async {
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

    final wantedIdsLower = {for (final id in tvgIds) id.toLowerCase()};
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

    // <channel> element state (name-fallback matching): the element's id and
    // the <display-name> being collected. Ids that matched a wanted name are
    // admitted to the programme filter alongside the explicit tvg-ids.
    String? channelElemId;
    StringBuffer? displayName;
    final nameToId = <String, String>{};
    final nameMatchedIds = <String>{};
    var sawWantedChannel = false;

    final events = bytes
        .transform(const Utf8Decoder(allowMalformed: true))
        .toXmlEvents();
    await for (final batch in events) {
      for (final event in batch) {
        if (event is XmlStartElementEvent) {
          switch (event.name) {
            case 'channel':
              String? id;
              for (final a in event.attributes) {
                if (a.name == 'id') id = a.value;
              }
              if (id != null &&
                  id.isNotEmpty &&
                  wantedIdsLower.contains(id.toLowerCase())) {
                sawWantedChannel = true;
              }
              // Unconditional (re)assignment: a self-closing or id-less
              // <channel> must also RESET the state, or (on malformed XML
              // missing a </channel>) its display-names would be attributed
              // to the previous channel's id.
              channelElemId = (wantedNames.isNotEmpty &&
                      !event.isSelfClosing &&
                      id != null &&
                      id.isNotEmpty)
                  ? id
                  : null;
            case 'display-name':
              if (channelElemId != null && !event.isSelfClosing) {
                displayName = StringBuffer();
                textTarget = displayName;
              }
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
              final chLower = ch?.toLowerCase();
              if (chLower != null &&
                  (wantedIdsLower.contains(chLower) ||
                      nameMatchedIds.contains(chLower))) {
                channel = chLower;
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
            case 'display-name':
              final name = displayName;
              final id = channelElemId;
              if (name != null && id != null) {
                final norm = normalizeChannelName(name.toString());
                // First guide channel carrying a name wins (Kodi semantics);
                // later duplicates would silently shadow real programmes.
                if (norm.isNotEmpty && wantedNames.contains(norm)) {
                  sawWantedChannel = true;
                  if (!nameToId.containsKey(norm)) {
                    nameToId[norm] = id.toLowerCase();
                    nameMatchedIds.add(id.toLowerCase());
                  }
                }
              }
              displayName = null;
              textTarget = null;
            case 'channel':
              channelElemId = null;
              displayName = null;
              textTarget = null;
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

    // DB mode: write the index here, on this worker isolate, and return a
    // light guide. An EMPTY index deliberately writes nothing — the caller
    // treats "matched nothing" against existing stored rows (a transient
    // provider hiccup must not wipe a still-useful guide).
    if (dbPath != null && guideKey != null && index.isNotEmpty) {
      IptvCatalogDb.ingestEpgGuide(
        dbPath: dbPath,
        guideKey: guideKey,
        epgUrl: epgUrl ?? '',
        byId: index,
        nameToId: nameToId,
        sawWanted: sawWantedChannel,
      );
      return XmltvGuide(
        byId: const {},
        nameToId: nameToId,
        sawWantedChannel: sawWantedChannel,
        guideKey: guideKey,
        channelCount: index.length,
      );
    }

    return XmltvGuide(
      byId: index,
      nameToId: nameToId,
      sawWantedChannel: sawWantedChannel,
    );
  }

  /// XMLTV time: `yyyyMMddHHmmss [±HHMM]`. Seconds and the offset are both
  /// optional in the wild; a missing offset is read as UTC — what both Kodi's
  /// pvr.iptvsimple and IPTVnator do, so guides authored against the major
  /// clients line up.
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
      return DateTime.utc(y, mo, d, h, mi, s).millisecondsSinceEpoch;
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
      // Keys lowercased on READ, not just trusted from disk: legacy v1
      // snapshots stored guide-original-case ids, and they remain the
      // network-failure fallback — served verbatim, their keys would miss
      // every lowercased lookup and the promised fallback would be dead.
      final index = <String, List<List<Object?>>>{
        for (final entry in channels.entries)
          entry.key.toLowerCase(): [
            for (final row in (entry.value as List))
              [
                (row[0] as num).toInt(),
                (row[1] as num).toInt(),
                row[2] as String,
                row[3] as String,
              ],
          ],
      };
      // Snapshots from before name matching (no 'names' map) or before
      // lowercase-id canonicalization (v < 2) predate the current index
      // shape. Treat them as stale (refresh promptly) but keep them usable
      // as the network-failure fallback.
      final namesRaw = decoded['names'];
      final nameToId = <String, String>{
        if (namesRaw is Map<String, dynamic>)
          for (final entry in namesRaw.entries)
            if (entry.value is String)
              entry.key: (entry.value as String).toLowerCase(),
      };
      return _Snapshot(
        guide: XmltvGuide(
          byId: index,
          nameToId: nameToId,
          sawWantedChannel: decoded['sawWanted'] == true,
        ),
        fetchedAt: fetchedAt,
        legacy: namesRaw is! Map<String, dynamic> ||
            (decoded['v'] as num? ?? 1) < 2,
      );
    } catch (e) {
      debugPrint('XmltvEpgSource: bad snapshot ${file.path}: $e');
      return null;
    }
  }

  static Future<void> _writeSnapshot(
    File file,
    String epgUrl,
    XmltvGuide guide,
  ) async {
    try {
      // Encode off the UI isolate — the index can run to several MB, and the
      // read path already offloads its decode for the same reason.
      final encoded = await compute(jsonEncode, <String, dynamic>{
        'v': 2, // 2 = lowercase-canonicalized channel ids
        'epgUrl': epgUrl,
        'fetchedAt': DateTime.now().toIso8601String(),
        'channels': guide.byId,
        'names': guide.nameToId,
        'sawWanted': guide.sawWantedChannel,
      });
      await file.writeAsString(encoded);
    } catch (e) {
      debugPrint('XmltvEpgSource: snapshot write failed: $e');
    }
  }
}

class _Snapshot {
  final XmltvGuide guide;
  final DateTime fetchedAt;

  /// Written before name matching existed — no 'names' map to serve from.
  final bool legacy;
  _Snapshot({required this.guide, required this.fetchedAt, this.legacy = false});

  bool get isStale =>
      legacy ||
      DateTime.now().difference(fetchedAt) >=
          (guide.byId.isEmpty
              ? XmltvEpgSource._emptyCacheTtl
              : XmltvEpgSource._cacheTtl);
}

/// Terminal sink for a chunked md5 conversion — holds the single digest the
/// hasher emits on close. (Avoids depending on package:convert's
/// AccumulatorSink for one value.)
class _SingleDigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
