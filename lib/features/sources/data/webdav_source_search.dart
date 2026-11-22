import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/torrent.dart';
import '../../../models/webdav_item.dart';
import '../../../services/diagnostic_log.dart';
import '../../../services/profiles/connection_resource_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/source_search_preferences.dart';
import '../../../services/webdav_protocol_client.dart';
import '../../../services/webdav_service.dart';
import '../../../services/webdav_source_tickets.dart';
import '../../../utils/file_utils.dart';
import '../models/webdav_source_status.dart';
import 'webdav_folder_names.dart';
import 'webdav_listing_cache.dart';
import 'webdav_title_matcher.dart';

typedef WebDavFolderLister =
    Future<List<WebDavItem>> Function(WebDavConfig config, String path);
typedef WebDavAccessCheck = Future<void> Function(WebDavConfig config);

/// How much one server may cost a Sources search.
final class WebDavSearchLimits {
  const WebDavSearchLimits({
    this.maxFolders = 40,
    this.maxLibraryDepth = 5,
    this.maxTitleDepth = 3,
    this.maxGuessesPerFolder = 12,
    this.maxGuessListing = 50,
    this.concurrency = 2,
    this.maxRows = 30,
    this.timeLimit = const Duration(seconds: 15),
    this.slowAfter = const Duration(seconds: 4),
    this.maxListingBytes = 8 * 1024 * 1024,
  });

  /// Folder listings per server; each is one request.
  final int maxFolders;

  /// Library/index levels opened while the title is still unseen.
  final int maxLibraryDepth;

  /// Levels opened below the title's own folder (seasons, packs).
  final int maxTitleDepth;

  /// A folder with more unrecognised sub-folders than this lists titles,
  /// not categories, so none of them is opened.
  final int maxGuessesPerFolder;

  /// A folder listing more sub-folders than this is a title list (a debrid
  /// folder, a big library), so none of its unrecognised ones is opened.
  final int maxGuessListing;
  final int concurrency;
  final int maxRows;
  final Duration timeLimit;

  /// When the progress line starts explaining why it takes a while.
  final Duration slowAfter;

  /// A flat debrid folder can list thousands of torrents.
  final int maxListingBytes;
}

/// Finds a title's files on the profile's WebDAV servers by folder and file
/// names. WebDAV has no search, so this opens the folders most likely to lead
/// to the title first, within [WebDavSearchLimits], and reports progress as
/// it goes.
final class WebDavSourceSearch {
  WebDavSourceSearch({
    Future<List<WebDavConfig>> Function()? servers,
    Future<bool> Function()? enabled,
    WebDavFolderLister? listFolder,
    WebDavAccessCheck? checkAccess,
    WebDavListingCache? cache,
    this.limits = const WebDavSearchLimits(),
  }) : _servers = servers ?? WebDavService.getConfigs,
       _enabled = enabled ?? _searchEnabled,
       _checkAccess = checkAccess ?? WebDavService.authorizeUse,
       _cache = cache ?? sharedCache {
    _listFolder = listFolder ?? _listWithLimit;
  }

  static final sharedCache = WebDavListingCache();

  final Future<List<WebDavConfig>> Function() _servers;
  final Future<bool> Function() _enabled;
  final WebDavAccessCheck _checkAccess;
  final WebDavListingCache _cache;
  late final WebDavFolderLister _listFolder;
  final WebDavSearchLimits limits;

  static Future<bool> _searchEnabled() async =>
      (await SourceSearchPreferences.readOrDefault()).webDav;

  Future<List<WebDavItem>> _listWithLimit(WebDavConfig config, String path) =>
      WebDavService.listDirectory(
        config: config,
        path: path,
        maxBytes: limits.maxListingBytes,
      );

  static String keyFor(WebDavConfig config) =>
      '${WebDavSourceTickets.prefix}${config.id}'.toLowerCase();

  /// Whether [selection] is something this search can look for: a title
  /// search (not a keyword or addon-specific episode) with a concrete episode
  /// for series.
  static bool supports(AdvancedSearchSelection selection) {
    final type = selection.contentType;
    if (type != null && type != 'movie' && type != 'series') return false;
    if (selection.hasStremioEpisodeIdentity) return false;
    return _target(selection).searchable;
  }

  static WebDavMatchTarget _target(
    AdvancedSearchSelection selection, {
    bool requireYear = false,
  }) => WebDavMatchTarget(
    title: selection.title,
    year: selection.year,
    isSeries: selection.isSeries,
    season: selection.season,
    episode: selection.episode,
    requireYear: requireYear,
    imdbId: selection.imdbId,
  );

  /// Servers that recently could not be reached, by key. Automatic playback
  /// skips them for [unreachableCooldown] so an offline NAS does not delay
  /// every play; the Sources page still tries them and says why they fail.
  static final _unreachableAt = <String, DateTime>{};
  static const unreachableCooldown = Duration(minutes: 5);

  @visibleForTesting
  static void resetUnreachable() => _unreachableAt.clear();

  static bool _recentlyUnreachable(String key) {
    final at = _unreachableAt[key];
    if (at == null) return false;
    if (DateTime.now().difference(at) < unreachableCooldown) return true;
    _unreachableAt.remove(key);
    return false;
  }

  /// Lists the servers a search would use, as `(key, name)`, for callers
  /// that offer each server separately (the player's source sheet).
  Future<List<(String, String)>> serverRefs() async {
    try {
      if (!await _enabled()) return const [];
      return [
        for (final config in await _servers())
          if (config.isComplete && !config.credentialsRedacted)
            (keyFor(config), _displayName(config)),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _displayName(WebDavConfig config) =>
      config.name.trim().isEmpty ? 'Server' : config.name.trim();

  /// Searches every usable server, at most two at a time. [onStatus] gets
  /// each progress change; [onRows] gets new matches as they are found.
  /// Never throws: a server's failure becomes its status.
  ///
  /// [onlyServerKey] limits the search to one server. [automatic] is for
  /// unattended picks: movies must state their year, and servers that just
  /// failed to answer are skipped.
  Future<List<WebDavSourceStatus>> search(
    AdvancedSearchSelection selection, {
    required void Function(WebDavSourceStatus status) onStatus,
    required void Function(String key, List<Torrent> rows) onRows,
    required bool Function() shouldContinue,
    String? onlyServerKey,
    bool automatic = false,
  }) async {
    if (!supports(selection)) return const [];
    final scope = ProfileRuntime.scope.value;
    bool active() => shouldContinue() && ProfileRuntime.scope.value == scope;
    List<WebDavConfig> servers;
    try {
      if (!await _enabled() || !active()) return const [];
      servers = [
        for (final config in await _servers())
          if (config.isComplete &&
              !config.credentialsRedacted &&
              (onlyServerKey == null || keyFor(config) == onlyServerKey) &&
              !(automatic && _recentlyUnreachable(keyFor(config))))
            config,
      ];
    } catch (_) {
      return const []; // No servers this profile may use.
    }
    if (servers.isEmpty || !active()) return const [];
    final target = _target(selection, requireYear: automatic);
    final results = <WebDavSourceStatus>[];
    var next = 0;
    Future<void> worker() async {
      while (next < servers.length && active()) {
        final config = servers[next++];
        final status = await _ServerWalk(
          search: this,
          config: config,
          matcher: WebDavTitleMatcher(target),
          target: target,
          active: active,
          onStatus: onStatus,
          onRows: onRows,
        ).run();
        if (status.unreachable) {
          _unreachableAt[status.key] = DateTime.now();
        } else if (status.phase != WebDavSearchPhase.failed) {
          _unreachableAt.remove(status.key);
        }
        results.add(status);
      }
    }

    await Future.wait(
      List.generate(servers.length < 2 ? servers.length : 2, (_) => worker()),
    );
    return active() ? List.unmodifiable(results) : const [];
  }
}

final class _Folder {
  const _Folder(
    this.path, {
    required this.depth,
    this.insideTitle = false,
    this.titleDepth = 0,
    this.season,
    this.guessed = false,
    this.guessChain = 0,
    this.order = 0,
  });

  final String path;
  final int depth;
  final bool insideTitle;
  final int titleDepth;
  final int? season;

  /// Opened on a guess that it groups titles ([WebDavFolderKind.guess]).
  final bool guessed;

  /// Guessed folders in a row down to this one ("HDD1/English" is 2).
  final int guessChain;

  /// Discovery order, so equally ranked folders keep their listing order.
  final int order;
}

/// What one server's walk opened and passed over, for diagnostics. Counts
/// only: folder names are private.
final class _WalkCounts {
  var titleFolders = 0;
  var libraryFolders = 0;
  var guessedFolders = 0;
  var droppedGuesses = 0;
  var skippedFolders = 0;
  var deepestLevel = 0;
}

/// One server's bounded, cancellable walk.
final class _ServerWalk {
  _ServerWalk({
    required this.search,
    required this.config,
    required this.matcher,
    required this.target,
    required this.active,
    required this.onStatus,
    required this.onRows,
  }) : status = WebDavSourceStatus(
         key: WebDavSourceSearch.keyFor(config),
         name: WebDavSourceSearch._displayName(config),
         phase: WebDavSearchPhase.searching,
       );

  final WebDavSourceSearch search;
  final WebDavConfig config;
  final WebDavTitleMatcher matcher;
  final WebDavMatchTarget target;
  final bool Function() active;
  final void Function(WebDavSourceStatus) onStatus;
  final void Function(String, List<Torrent>) onRows;
  WebDavSourceStatus status;

  final _queue = <_Folder>[];
  final _opened = <String>{};
  final _found = <String>{};
  final _counts = _WalkCounts();
  var _queued = 0;
  var _finished = false;

  WebDavSearchLimits get _limits => search.limits;

  void _publish(WebDavSourceStatus next) {
    status = next;
    if (!_finished && active()) onStatus(next);
  }

  Future<WebDavSourceStatus> run() async {
    _publish(status);
    final slowTimer = Timer(_limits.slowAfter, () {
      if (status.searching) _publish(status.copyWith(slow: true));
    });
    final deadline = DateTime.now().add(_limits.timeLimit);
    _queue.add(const _Folder('', depth: 0));
    try {
      while (_queue.isNotEmpty && active()) {
        if (status.foldersChecked >= _limits.maxFolders) {
          return _finish(WebDavSearchPhase.folderLimit);
        }
        if (_found.length >= _limits.maxRows) break;
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) return _timedOut();
        final wave = _takeWave();
        final listings = await Future.wait([
          for (final folder in wave) _list(folder),
        ]).timeout(remaining, onTimeout: () => <List<WebDavItem>?>[]);
        if (!active()) break;
        if (listings.isEmpty && wave.isNotEmpty) return _timedOut();
        final rows = <Torrent>[];
        var failed = 0;
        for (var i = 0; i < wave.length; i++) {
          final items = listings[i];
          if (items == null) {
            failed++;
            continue;
          }
          rows.addAll(await _visit(wave[i], items));
          if (!active()) break;
        }
        _publish(
          status.copyWith(
            foldersChecked: status.foldersChecked + wave.length,
            failedFolders: status.failedFolders + failed,
            found: status.found + rows.length,
          ),
        );
        if (rows.isNotEmpty && active()) onRows(status.key, rows);
      }
      return _finish(WebDavSearchPhase.done);
    } on _WalkFailure catch (failure) {
      return _finish(
        WebDavSearchPhase.failed,
        failure: failure.failure,
        unreachable: failure.unreachable,
      );
    } catch (_) {
      // Never leave a server showing "searching" because of a bug.
      return _finish(WebDavSearchPhase.failed, failure: WebDavFailure.other);
    } finally {
      slowTimer.cancel();
      _finished = true;
    }
  }

  /// A server that never answered its first listing counts as unreachable.
  WebDavSourceStatus _timedOut() => _finish(
    WebDavSearchPhase.timedOut,
    unreachable: status.foldersChecked == 0,
  );

  WebDavSourceStatus _finish(
    WebDavSearchPhase phase, {
    WebDavFailure? failure,
    bool unreachable = false,
  }) {
    final summary = status.copyWith(
      phase: phase,
      failure: failure,
      unreachable: unreachable,
    );
    _publish(summary);
    _log(summary, stopped: !active());
    return summary;
  }

  void _log(WebDavSourceStatus summary, {required bool stopped}) {
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_source',
      event: 'title_search_completed',
      fields: {
        'outcome': DiagnosticLabel(summary.phase.name),
        'stopped': stopped,
        'failure': summary.failure == null
            ? null
            : DiagnosticLabel(summary.failure!.name),
        'automatic': target.requireYear,
        'series': target.isSeries,
        'folders_checked': summary.foldersChecked,
        'folders_failed': summary.failedFolders,
        'found': summary.found,
        'title_folders': _counts.titleFolders,
        'library_folders': _counts.libraryFolders,
        'guessed_folders': _counts.guessedFolders,
        'dropped_guesses': _counts.droppedGuesses,
        'skipped_folders': _counts.skippedFolders,
        'deepest_level': _counts.deepestLevel,
        'left_unchecked': _queue.length,
      },
    );
  }

  /// Title folders first (they hold the answer), then library folders, then
  /// guesses; shallower first, and in listing order among equals.
  List<_Folder> _takeWave() {
    // Guesses only help find the title; once it is found they cost time.
    if (_found.isNotEmpty) {
      final before = _queue.length;
      _queue.removeWhere((folder) => folder.guessed);
      _counts.droppedGuesses += before - _queue.length;
    }
    _queue.sort((a, b) {
      if (a.insideTitle != b.insideTitle) return a.insideTitle ? -1 : 1;
      if (a.guessed != b.guessed) return a.guessed ? 1 : -1;
      final depth = a.depth.compareTo(b.depth);
      return depth != 0 ? depth : a.order.compareTo(b.order);
    });
    final room = _limits.maxFolders - status.foldersChecked;
    // A wave waits for its slowest listing, so a guess (a sleeping drive, a
    // huge folder) never shares one with a folder that may hold the title.
    final firstGuess = _queue.indexWhere((folder) => folder.guessed);
    final sameKind = firstGuess <= 0 ? _queue.length : firstGuess;
    final count = [
      _limits.concurrency,
      room,
      sameKind,
    ].reduce((a, b) => a < b ? a : b);
    final wave = _queue.sublist(0, count);
    _queue.removeRange(0, count);
    for (final folder in wave) {
      if (folder.depth > _counts.deepestLevel) {
        _counts.deepestLevel = folder.depth;
      }
    }
    return wave;
  }

  /// Null when this folder could not be listed; the walk goes on without it.
  /// The server's top folder failing ends the walk with a reason instead.
  Future<List<WebDavItem>?> _list(_Folder folder) async {
    final cacheKey = [
      ProfileRuntime.scope.value?.profileId,
      config.id,
      config.connectionResourceRevision,
      config.baseUrl,
      config.username,
      folder.path,
    ].join('\u0000');
    try {
      final cached = search._cache.get(cacheKey);
      if (cached != null) {
        await search._checkAccess(config);
        return cached;
      }
      final items = await search._listFolder(config, folder.path);
      search._cache.put(cacheKey, items);
      return items;
    } on WebDavException catch (error) {
      if (folder.depth == 0 && !folder.insideTitle) {
        throw _WalkFailure(
          _reason(error),
          unreachable: const {
            WebDavErrorKind.timeout,
            WebDavErrorKind.network,
            WebDavErrorKind.tls,
          }.contains(error.kind),
        );
      }
      if (error.kind == WebDavErrorKind.authentication) {
        throw _WalkFailure(_reason(error));
      }
      return null;
    } on ResourceAuthorizationException {
      // Access was revoked or the server changed under this profile.
      throw const _WalkFailure(WebDavFailure.noAccess);
    } catch (_) {
      // Anything else unexpected: skip the folder, or stop at the top folder.
      if (folder.depth == 0 && !folder.insideTitle) {
        throw const _WalkFailure(WebDavFailure.other);
      }
      return null;
    }
  }

  static WebDavFailure _reason(WebDavException error) => switch (error.kind) {
    WebDavErrorKind.authentication => WebDavFailure.signIn,
    WebDavErrorKind.timeout ||
    WebDavErrorKind.network ||
    WebDavErrorKind.tls ||
    WebDavErrorKind.transient => WebDavFailure.unreachable,
    WebDavErrorKind.notFound => WebDavFailure.notFound,
    WebDavErrorKind.invalidRequest when error.message.contains('byte limit') =>
      WebDavFailure.tooLarge,
    _ => WebDavFailure.other,
  };

  /// Items are checked in short bursts, yielding to the UI thread whenever
  /// a burst has run for [_burst], so even a huge folder and a short title
  /// (no cheap prefilter for "It") never hold a frame.
  static const _burst = Duration(milliseconds: 4);

  Future<List<Torrent>> _visit(_Folder folder, List<WebDavItem> items) async {
    final rows = <Torrent>[];
    final guesses = <WebDavItem>[];
    var holdsTitle = false;
    var folders = 0;
    var holdsRelease = false;
    final clock = Stopwatch()..start();
    for (var i = 0; i < items.length; i++) {
      if (i % 32 == 31 && clock.elapsed > _burst) {
        await Future<void>.delayed(Duration.zero);
        if (!active()) return rows;
        clock.reset();
      }
      final item = items[i];
      if (item.isDirectory) {
        folders++;
        if (folder.guessed && !holdsRelease) {
          holdsRelease = !WebDavFolderNames.mayBeCategory(item.name);
        }
        switch (_consider(folder, item)) {
          case WebDavFolderKind.title:
            holdsTitle = true;
          case WebDavFolderKind.guess:
            guesses.add(item);
          case _:
        }
      } else if (folder.guessed && !holdsRelease && _isVideo(item)) {
        holdsRelease = true;
      }
      if (!item.isDirectory &&
          _found.length < _limits.maxRows &&
          _isVideo(item) &&
          !_found.contains(item.path) &&
          matcher.matchesFile(
            item.name,
            insideTitle: folder.insideTitle,
            season: folder.season,
            sizeBytes: item.sizeBytes,
          )) {
        _found.add(item.path);
        rows.add(_row(item, folder));
        holdsTitle = true;
      }
    }
    _guess(
      folder,
      guesses,
      holdsTitle: holdsTitle,
      folders: folders,
      holdsRelease: holdsRelease,
    );
    return rows;
  }

  static bool _isVideo(WebDavItem item) =>
      FileUtils.isVideoFile(item.name) ||
      (item.contentType?.toLowerCase().startsWith('video/') ?? false);

  /// Opens a folder's unrecognised sub-folders last, unless the folder
  /// already held the title (its other folders are other titles), lists too
  /// many folders to be a list of categories, or is itself a guess that
  /// turned out to be some other title (it holds videos or releases).
  void _guess(
    _Folder parent,
    List<WebDavItem> guesses, {
    required bool holdsTitle,
    required int folders,
    required bool holdsRelease,
  }) {
    if (guesses.isEmpty) return;
    if (holdsTitle ||
        guesses.length > _limits.maxGuessesPerFolder ||
        folders > _limits.maxGuessListing ||
        (parent.guessed && (holdsRelease || parent.guessChain >= 2)) ||
        parent.depth + 1 > _limits.maxLibraryDepth) {
      _counts.droppedGuesses += guesses.length;
      return;
    }
    _counts.guessedFolders += guesses.length;
    for (final item in guesses) {
      _queue.add(
        _Folder(
          item.path,
          depth: parent.depth + 1,
          guessed: true,
          guessChain: parent.guessed ? parent.guessChain + 1 : 1,
          order: _queued++,
        ),
      );
    }
  }

  /// Queues [item] unless it is a guess, which [_guess] decides per folder.
  WebDavFolderKind _consider(_Folder parent, WebDavItem item) {
    if (!_opened.add(item.path)) return WebDavFolderKind.skip;
    if (parent.insideTitle) {
      if (parent.titleDepth >= _limits.maxTitleDepth) {
        return WebDavFolderKind.skip;
      }
      final decision = matcher.innerFolder(item.name, season: parent.season);
      if (decision.kind == WebDavFolderKind.skip) return decision.kind;
      _queue.add(
        _Folder(
          item.path,
          depth: parent.depth + 1,
          insideTitle: true,
          titleDepth: parent.titleDepth + 1,
          season: decision.season,
          order: _queued++,
        ),
      );
      return decision.kind;
    }
    final decision = matcher.libraryFolder(item.name);
    switch (decision.kind) {
      case WebDavFolderKind.skip:
        _counts.skippedFolders++;
      case WebDavFolderKind.guess:
        break;
      case WebDavFolderKind.title:
        _counts.titleFolders++;
        _queue.add(
          _Folder(
            item.path,
            depth: parent.depth + 1,
            insideTitle: true,
            titleDepth: 1,
            season: decision.season,
            order: _queued++,
          ),
        );
      case WebDavFolderKind.browse:
        if (parent.depth + 1 > _limits.maxLibraryDepth) {
          _counts.skippedFolders++;
          return WebDavFolderKind.skip;
        }
        _counts.libraryFolders++;
        _queue.add(
          _Folder(item.path, depth: parent.depth + 1, order: _queued++),
        );
    }
    return decision.kind;
  }

  Torrent _row(WebDavItem item, _Folder folder) {
    final episode = target.isSeries
        ? 'S${target.season.toString().padLeft(2, '0')}'
              'E${target.episode.toString().padLeft(2, '0')}'
        : null;
    final where = folder.path.replaceAll(RegExp(r'/+$'), '');
    final torrent = Torrent(
      rowid: 0,
      infohash: sha256
          .convert(utf8.encode('${status.key}:${item.path}'))
          .toString(),
      name: item.name,
      sizeBytes: item.sizeBytes ?? 0,
      createdUnix: (item.modifiedAt?.millisecondsSinceEpoch ?? 0) ~/ 1000,
      seeders: 0,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
      source: status.key,
      hasRealInfoHash: false,
      streamType: StreamType.directUrl,
      directUrl: WebDavService.directUrl(config, item.path),
      httpHeaders: WebDavService.authHeaders(config),
      addonDisplayName: status.label,
      streamLabel: status.label,
      streamDescription: where.isEmpty ? null : where,
      streamOriginalTitle: item.name,
      coverageType: target.isSeries ? 'singleEpisode' : null,
      seasonNumber: target.isSeries ? target.season : null,
      episodeIdentifier: episode,
    );
    final scope = ProfileRuntime.scope.value;
    WebDavSourceTickets.register(torrent, () async {
      if (ProfileRuntime.scope.value != scope) {
        throw StateError('Profile changed.');
      }
      await search._checkAccess(config);
    });
    return torrent;
  }
}

final class _WalkFailure implements Exception {
  const _WalkFailure(this.failure, {this.unreachable = false});

  final WebDavFailure failure;
  final bool unreachable;
}
