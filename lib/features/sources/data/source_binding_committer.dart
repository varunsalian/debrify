import '../../../models/playback_meta.dart';
import '../../../models/series_source.dart';
import '../../../models/torrent.dart';
import '../../../services/source_selection_diagnostics.dart';
import 'automatic_source_bindings.dart';

/// One player's validated writes, ordered and owned independently of its view.
class SourceBindingCommitter {
  SourceBindingCommitter({
    required this.bindings,
    required this.meta,
    required this.chooseProvider,
    this.provider,
    this.lazy = false,
  });

  final AutomaticSourceBindings bindings;
  final PlaybackMeta? meta;
  final String? provider;
  final bool lazy;
  final Future<String?> Function(bool Function() canContinue) chooseProvider;
  bool _initialPending = true;
  bool _closed = false;
  bool _launchClosed = false;
  int _retainedSessions = 0;
  Future<void> _tail = Future<void>.value();

  bool get isCurrent => !_closed && bindings.isCurrent;

  /// Native launch returns before playback ends. Its persistence session owns
  /// this additional lease until its accepted writes drain or it retires.
  void Function() retain() {
    if (_closed) return () {};
    _retainedSessions++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _retainedSessions--;
      if (_launchClosed && _retainedSessions == 0) _closed = true;
    };
  }

  void close() {
    _launchClosed = true;
    if (_retainedSessions == 0) _closed = true;
  }

  Future<void> call(Torrent source) {
    if (!isCurrent) return Future<void>.value();
    final initial = _initialPending;
    _initialPending = false;
    final task = _tail.then(
      (_) => bindings.runOwned(() => isCurrent, () async {
        bool active() => isCurrent;
        if (!active()) return;
        if (lazy) {
          if (source.streamType == StreamType.directUrl) {
            await bindings.cacheDirect(meta, source, canContinue: active);
            if (!active()) return;
            await bindings.switchSource(
              meta,
              source,
              SeriesSource.addonDirectService,
              canContinue: active,
            );
            return;
          }
          final selected = provider ?? await chooseProvider(active);
          if (selected == null || !active()) return;
          await bindings.switchSource(
            meta,
            source,
            selected,
            canContinue: active,
          );
          return;
        }
        logSourceSelection(
          'validated_source',
          source: source,
          season: meta?.season,
          episode: meta?.episode,
          reason: initial ? 'initial_playback' : 'player_switch',
        );
        await bindings.cacheDirect(meta, source, canContinue: active);
        if (!active()) return;
        var selected = provider!;
        if (source.streamType == StreamType.torrent &&
            [
              SeriesSource.addonDirectService,
              SeriesSource.mediaServerService,
              SeriesSource.iptvDirectService,
            ].contains(selected)) {
          selected = await chooseProvider(active) ?? selected;
        }
        if (!active()) return;
        if (initial) {
          await bindings.bindMovie(meta, source, selected, canContinue: active);
          if (!active()) return;
          await bindings.bindSeries(
            meta,
            source,
            selected,
            canContinue: active,
          );
        } else {
          await bindings.switchSource(
            meta,
            source,
            selected,
            canContinue: active,
          );
        }
      }),
    );
    _tail = task.catchError((_) {});
    return task;
  }
}
