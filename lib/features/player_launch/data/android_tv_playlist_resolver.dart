import 'dart:math';
import 'package:collection/collection.dart';
import 'package:debrify/features/player_launch/data/stream_redirect_resolver.dart';
import 'package:debrify/features/player_launch/models/launcher_entry.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:flutter/foundation.dart';

class AndroidTvPlaylistResolver {
  List<LauncherEntry> entries;
  final Future<String> Function(
    PlaylistEntry entry, {
    bool Function()? canContinue,
  })
  resolveEntry;

  // Monotonic token for in-flight source switches. The native side already
  // discards stale playlist RESULTS via its own resolution token, but the Dart
  // `replaceEntries` side effect was ungated: tap B then C quickly and, if B's
  // torrent resolves slower, B's `replaceEntries` could run LAST and leave the
  // lazy stream resolver pointing at B while the player shows C — wrong-torrent
  // lazy resolution. Each switch captures a token via [beginSwitch]; a late
  // [replaceEntries] whose token is no longer current is ignored.
  int _switchSeq = 0;
  bool _disposed = false;
  int beginSwitch() => ++_switchSeq;
  bool isLatestSwitch(int token) => !_disposed && token == _switchSeq;

  AndroidTvPlaylistResolver({
    required this.entries,
    required this.resolveEntry,
  });

  /// Replace entries with a new playlist (used during source switching).
  /// Pass the [switchToken] from [beginSwitch] so a stale (superseded) switch
  /// that resolves late is skipped instead of overwriting a newer source.
  void replaceEntries(List<PlaylistEntry> playlistEntries, {int? switchToken}) {
    if (_disposed || (switchToken != null && switchToken != _switchSeq)) {
      debugPrint(
        'AndroidTvPlaylistResolver: skipping stale replaceEntries '
        '(token $switchToken != current $_switchSeq)',
      );
      return;
    }
    // Clear cached URLs for old entries before replacing
    StreamRedirectResolver.clearResolvedStreams(entries.map((e) => e.resumeId));

    entries = playlistEntries.asMap().entries.map((e) {
      final i = e.key;
      final entry = e.value;
      return LauncherEntry(
        entry: entry,
        index: i,
        resumeId: '${entry.title}_$i',
      );
    }).toList();
    debugPrint(
      'AndroidTvPlaylistResolver: replaced entries with ${entries.length} new entries',
    );
  }

  Future<Map<String, dynamic>?> handleRequest(
    Map<String, dynamic> request,
  ) async {
    final token = _switchSeq;
    bool active() => isLatestSwitch(token);
    if (!active()) return null;
    debugPrint(
      'AndroidTvPlaylistResolver: handleRequest called with: $request',
    );
    debugPrint('AndroidTvPlaylistResolver: total entries: ${entries.length}');

    LauncherEntry? target;
    final resumeId = request['resumeId'] as String?;
    final index = request['index'] as int?;

    debugPrint(
      'AndroidTvPlaylistResolver: looking for - resumeId: $resumeId, index: $index',
    );

    if (resumeId != null) {
      target = entries.firstWhereOrNull((entry) => entry.resumeId == resumeId);
      debugPrint(
        'AndroidTvPlaylistResolver: found by resumeId: ${target != null}',
      );
    }
    if (target == null && index != null && index >= 0 && index < entries.length) {
      target = entries[index];
      debugPrint(
        'AndroidTvPlaylistResolver: found by index: ${true}, entry: ${target.entry.title}',
      );
    }
    if (target == null) {
      debugPrint('AndroidTvPlaylistResolver: ERROR - target not found!');
      debugPrint('AndroidTvPlaylistResolver: Available entries:');
      for (int i = 0; i < entries.length; i++) {
        debugPrint(
          '  [$i] resumeId=${entries[i].resumeId}, title=${entries[i].entry.title}',
        );
      }
      return null;
    }

    debugPrint(
      'AndroidTvPlaylistResolver: resolving entry for: ${target.entry.title}',
    );
    final url = await resolveEntry(target.entry, canContinue: active);
    if (!active()) return null;
    debugPrint(
      'AndroidTvPlaylistResolver: resolved URL: ${url.isNotEmpty ? url.substring(0, min(50, url.length)) : "EMPTY"}',
    );

    if (url.isEmpty) {
      debugPrint('AndroidTvPlaylistResolver: ERROR - resolved URL is empty!');
      return null;
    }

    StreamRedirectResolver.cacheResolvedStream(target.resumeId, url);
    debugPrint(
      'AndroidTvPlaylistResolver: returning success - url length: ${url.length}',
    );
    return {
      'url': url,
      'resumeId': target.resumeId,
      'index': target.index,
      'provider': target.entry.provider,
    };
  }

  void dispose() {
    _disposed = true;
    StreamRedirectResolver.clearResolvedStreams(entries.map((e) => e.resumeId));
  }
}
