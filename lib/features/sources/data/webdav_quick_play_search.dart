import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/quick_play_rules.dart';
import '../../../models/torrent.dart';
import '../../../services/diagnostic_log.dart';
import '../application/source_search_plans.dart';
import '../models/webdav_source_status.dart';
import 'iptv_quick_play_search.dart';
import 'webdav_source_search.dart';

/// WebDAV candidates for unattended playback: Quick Play, the next episode,
/// recovery after a failed source, and the player's own source search.
///
/// Runs on a tighter budget than the Sources page so a slow server cannot
/// hold playback up, skips servers that recently did not answer, and only
/// picks a movie whose folder or file states the release year.
final class WebDavQuickPlaySearch {
  const WebDavQuickPlaySearch._();

  static const limits = WebDavSearchLimits(
    maxFolders: 30,
    timeLimit: Duration(seconds: 6),
    slowAfter: Duration(seconds: 2),
  );

  /// Same eligibility as IPTV direct links: the rules must allow direct links
  /// and addon-family sources. Never throws.
  static Future<List<Torrent>> search(
    String id,
    String title,
    String? year,
    bool isMovie,
    int? season,
    int? episode,
    QuickPlayRules rules,
    bool Function()? isCancelled, {
    void Function(String? note)? onNote,
    @visibleForTesting WebDavSourceSearch? engine,
  }) async {
    if (!rules.allowDirectLinks ||
        !SourceSearchPlans.allowsAddonSearch(rules)) {
      return const [];
    }
    final selection = AdvancedSearchSelection(
      imdbId: id,
      title: title,
      year: year,
      isSeries: !isMovie,
      season: isMovie ? null : season,
      episode: isMovie ? null : episode,
    );
    if (!WebDavSourceSearch.supports(selection)) return const [];
    final rows = <Torrent>[];
    var noted = false;
    final watch = Stopwatch()..start();
    try {
      final statuses = await (engine ?? WebDavSourceSearch(limits: limits))
          .search(
            selection,
            automatic: true,
            shouldContinue: () => !(isCancelled?.call() ?? false),
            onRows: (_, found) => rows.addAll(found),
            onStatus: (status) {
              if (status.searching && status.slow) {
                noted = true;
                onNote?.call(status.progressMessage);
              }
            },
          );
      _log(statuses, rows.length, watch.elapsedMilliseconds);
      if (isCancelled?.call() ?? false) return const [];
      return List.unmodifiable(rows);
    } catch (_) {
      return const [];
    } finally {
      if (noted) onNote?.call(null);
    }
  }

  /// How long WebDAV may still run once other sources already gave usable
  /// candidates. Its full budget applies only when nothing else was found.
  static const graceAfterOthers = Duration(seconds: 1);

  /// Starts a search that [settle] can stop early. Notes it shows on the play
  /// loader are cleared when it stops, and none appear afterwards.
  static WebDavQuickPlayRun start(
    String id,
    String title,
    String? year,
    bool isMovie,
    int? season,
    int? episode,
    QuickPlayRules rules,
    bool Function()? isCancelled, {
    void Function(String? note)? onNote,
    @visibleForTesting WebDavSourceSearch? engine,
  }) {
    final run = WebDavQuickPlayRun._(onNote);
    run.rows = search(
      id,
      title,
      year,
      isMovie,
      season,
      episode,
      rules,
      () => run._stopped || (isCancelled?.call() ?? false),
      onNote: run._note,
      engine: engine,
    );
    // Started before other awaits; mark observed. It never throws anyway.
    run.rows.ignore();
    return run;
  }

  /// Waits for [run]: briefly when [haveOthers], otherwise for its own
  /// (bounded) budget. A run cut short is stopped, so it sends no more
  /// requests and leaves no note behind. Never throws.
  static Future<List<Torrent>> settle(
    WebDavQuickPlayRun run, {
    required bool haveOthers,
  }) async {
    try {
      return haveOthers
          ? await run.rows.timeout(
              graceAfterOthers,
              onTimeout: () => const <Torrent>[],
            )
          : await run.rows;
    } catch (_) {
      return const <Torrent>[];
    } finally {
      run.stop();
    }
  }

  /// IPTV and WebDAV direct candidates, started together. Await the result
  /// with [collect] after the addon search so WebDAV adds no wait of its own.
  static ({Future<List<Torrent>> iptv, WebDavQuickPlayRun webDav})
  startWithIptv(
    String id,
    String title,
    String? year,
    bool isMovie,
    int? season,
    int? episode,
    QuickPlayRules rules,
    bool Function()? isCancelled,
  ) {
    final iptv = IptvQuickPlaySearch.searchIptvForQuickPlay(
      id,
      title,
      year,
      isMovie,
      season,
      episode,
      rules,
      isCancelled,
    );
    // Started before the addon request: if that request throws, nobody
    // awaits it, so mark it observed. [collect] still sees any error.
    iptv.ignore();
    return (
      iptv: iptv,
      webDav: start(
        id,
        title,
        year,
        isMovie,
        season,
        episode,
        rules,
        isCancelled,
      ),
    );
  }

  /// IPTV in full, then WebDAV with a short grace when anything usable is
  /// already in hand ([haveOthers], or IPTV rows).
  static Future<List<Torrent>> collect(
    ({Future<List<Torrent>> iptv, WebDavQuickPlayRun webDav}) pending, {
    required bool haveOthers,
  }) async {
    try {
      final iptv = await pending.iptv;
      final webDav = await settle(
        pending.webDav,
        haveOthers: haveOthers || iptv.isNotEmpty,
      );
      return [...iptv, ...webDav];
    } finally {
      pending.webDav.stop();
    }
  }

  static void _log(List<WebDavSourceStatus> statuses, int found, int ms) {
    if (statuses.isEmpty) return;
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_source',
      event: 'quick_play_search_completed',
      fields: {
        'servers': statuses.length,
        'found': found,
        'elapsed_ms': ms,
        'outcomes': DiagnosticLabel(
          statuses.map((status) => status.phase.name).join('+'),
        ),
      },
    );
  }
}

/// One WebDAV search for unattended playback, stoppable by [stop].
final class WebDavQuickPlayRun {
  WebDavQuickPlayRun._(this._onNote);

  final void Function(String? note)? _onNote;
  late final Future<List<Torrent>> rows;
  var _stopped = false;
  var _noting = false;

  void _note(String? note) {
    if (_stopped) return;
    _noting = note != null;
    _onNote?.call(note);
  }

  /// Ends the search and clears its loader note, once.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    if (_noting) _onNote?.call(null);
    _noting = false;
  }
}
