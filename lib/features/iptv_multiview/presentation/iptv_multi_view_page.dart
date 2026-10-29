// The multi-view screen: a grid of IPTV tiles, one TrailerEngine each. The
// page owns every engine's lifetime (created from initState/listenManual,
// never from build), keeps engines keyed by channel url so tiles that move
// reuse their engine, and tears engines down before handing off to the
// full-screen player so the two never compete for a decoder.
import 'dart:async';

import 'package:debrify/features/iptv_multiview/application/multi_view_selection_notifier.dart';
import 'package:debrify/features/iptv_multiview/models/multi_view_selection.dart';
import 'package:debrify/features/iptv_multiview/presentation/multi_view_tile.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/trailer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the engine for one tile. [tileCount] is the number of tiles at the
/// moment the channel was added.
typedef MultiViewEngineFactory =
    Future<TrailerEngine> Function(
      IptvChannel channel, {
      required int tileCount,
    });

/// The multi-view page: black scaffold, no app bar, [multiViewGrid] tiles.
class IptvMultiViewPage extends ConsumerStatefulWidget {
  const IptvMultiViewPage({
    super.key,
    required this.engineFactory,
    required this.onWatchFullScreen,
  });

  final MultiViewEngineFactory engineFactory;

  /// Called after the page popped itself and every engine finished disposing.
  final void Function(IptvChannel channel) onWatchFullScreen;

  @override
  ConsumerState<IptvMultiViewPage> createState() => _IptvMultiViewPageState();
}

/// One tile slot's playback state: its engine (null while the factory runs
/// or after retirement) plus whether playback failed.
class _TileEntry {
  _TileEntry(this.channelName);

  final String channelName;
  TrailerEngine? engine;

  /// True once this slot left the grid; late results must not resurrect it.
  bool retired = false;
  bool failed = false;
}

class _IptvMultiViewPageState extends ConsumerState<IptvMultiViewPage> {
  /// Tile slots keyed by channel url; entries are reused when tiles move.
  final Map<String, _TileEntry> _entries = {};

  /// Dispose futures of every engine this page created. The full-screen
  /// handoff awaits them; page teardown keeps them too.
  final List<Future<void>> _disposeFutures = [];

  MultiViewSelection? _synced;

  @override
  void initState() {
    super.initState();
    // Engines come from lifecycle hooks only — never from build(). The
    // initial sync happens before the first frame so every tile starts its
    // factory immediately; the manual listener keeps later changes in step.
    // (listenManual subscriptions end with this widget, nothing to close.)
    ref.listenManual(
      multiViewSelectionProvider,
      (previous, next) => _onSelectionChanged(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    // The page is gone: detach every engine now and dispose them right away.
    // Slots still waiting on the factory are retired too, so the engine
    // they get is disposed on arrival.
    for (final entry in _entries.values) {
      entry.retired = true;
      final engine = entry.engine;
      if (engine == null) continue;
      entry.engine = null;
      engine.detach();
      _disposeFutures.add(engine.dispose());
    }
    super.dispose();
  }

  // --- Engine lifecycle -----------------------------------------------------

  void _onSelectionChanged(MultiViewSelection selection) {
    // The first call comes from initState (fireImmediately), where the
    // first build follows anyway and setState is not allowed.
    final first = _synced == null;
    _syncEngines(selection);
    if (!first && mounted) setState(() {});
  }

  /// The channels that should currently have a tile (empty when the owner
  /// changed: another profile's channels never render, nor play).
  List<IptvChannel> _visibleChannels(MultiViewSelection selection) {
    if (selection.owner != ref.read(multiViewOwnerProvider)()) {
      return const [];
    }
    return selection.channels;
  }

  void _syncEngines(MultiViewSelection selection) {
    final visible = _visibleChannels(selection);
    final visibleUrls = visible.map((c) => c.url).toSet();

    for (final url in _entries.keys.toList()) {
      if (visibleUrls.contains(url)) continue;
      // A retired slot frees its url at once, so a channel that left and
      // came back gets a fresh engine; an in-flight factory for the old slot
      // sees it no longer owns the url and disposes what it gets.
      _retire(_entries.remove(url)!, disposeNow: false);
    }

    _synced = selection;
    if (visible.isEmpty) return;

    final tileCount = visible.length;
    for (final channel in visible) {
      final existing = _entries[channel.url];
      if (existing != null && existing.engine != null) continue;
      final entry = existing ?? _TileEntry(channel.name);
      _entries[channel.url] = entry;
      unawaited(_startEngine(channel, entry, tileCount));
    }
  }

  void _retire(_TileEntry entry, {required bool disposeNow}) {
    entry.retired = true;
    final engine = entry.engine;
    if (engine == null) return;
    entry.engine = null;
    engine.detach();
    if (disposeNow) {
      _disposeFutures.add(engine.dispose());
      return;
    }
    // Release the render surface only after the tile's video widget
    // unmounted, i.e. after the frame that drops this tile.
    _disposeFutures.add(_disposeAfterFrame(engine));
  }

  Future<void> _disposeAfterFrame(TrailerEngine engine) async {
    final frame = Completer<void>();
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!frame.isCompleted) frame.complete();
      })
      ..scheduleFrame();
    await frame.future;
    await engine.dispose();
  }

  Future<void> _startEngine(
    IptvChannel channel,
    _TileEntry entry,
    int tileCount,
  ) async {
    final url = channel.url;
    final selection = _synced;
    final isAudioTile =
        selection != null &&
        selection.channels.isNotEmpty &&
        selection
                .channels[selection.audioIndex % selection.channels.length]
                .url ==
            url;
    TrailerEngine engine;
    try {
      engine = await widget.engineFactory(channel, tileCount: tileCount);
    } catch (error, stack) {
      _report('multi-view engine factory failed', error, stack);
      if (_stillShows(entry, url)) setState(() => entry.failed = true);
      return;
    }
    // The channel left the selection (or the page went away) while the
    // factory was running: hand the engine straight back, never open it.
    if (!_stillShows(entry, url)) {
      engine.detach();
      _disposeFutures.add(engine.dispose());
      if (_entries[url] == entry) _entries.remove(url);
      return;
    }
    entry.engine = engine;
    try {
      await engine.open(
        videoUrl: channel.url,
        // The page owns volume: the sound tile plays at 100, every other
        // tile stays muted (initial volumes are 100/0 by contract).
        volume: isAudioTile ? 100 : 0,
        loop: false,
        httpHeaders: channel.playbackHeaders,
      );
    } catch (error, stack) {
      _report('multi-view tile open failed', error, stack);
      // No video widget ever mounted for this engine, so it can go now.
      _retire(entry, disposeNow: true);
      if (mounted) setState(() => entry.failed = true);
      return;
    }
    if (!_stillShows(entry, url)) {
      _retire(entry, disposeNow: true);
      return;
    }
    if (mounted) setState(() {});
  }

  /// Whether [entry] still owns the live slot for [url] and that slot is on
  /// screen (so its engine's output would actually be rendered).
  bool _stillShows(_TileEntry entry, String url) {
    if (!mounted || entry.retired) return false;
    if (_entries[url] != entry) return false;
    return _visibleChannels(
      ref.read(multiViewSelectionProvider),
    ).any((c) => c.url == url);
  }

  void _report(String context, Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        context: ErrorDescription(context),
      ),
    );
  }

  // --- Interaction ----------------------------------------------------------

  void _applyAudio(int index) {
    final selection = ref.read(multiViewSelectionProvider);
    if (index < 0 || index >= selection.channels.length) return;
    ref.read(multiViewSelectionProvider.notifier).setAudio(index);
    for (var i = 0; i < selection.channels.length; i++) {
      final engine = _entries[selection.channels[i].url]?.engine;
      // One owner for volumes: the tapped tile goes to 100, everything
      // else back to 0 (fire-and-forget: engines never reject a volume).
      unawaited(engine?.setVolume(i == index ? 100 : 0) ?? Future.value());
    }
    setState(() {});
  }

  Future<void> _watchFullScreen(int index) async {
    final selection = ref.read(multiViewSelectionProvider);
    if (index < 0 || index >= selection.channels.length) return;
    final channel = selection.channels[index];
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;
    // Pop first, then release every decoder: the full player must never
    // compete with a tile for one.
    navigator.pop();
    await _disposeAllEngines();
    widget.onWatchFullScreen(channel);
  }

  Future<void> _disposeAllEngines() async {
    for (final entry in _entries.values) {
      final engine = entry.engine;
      if (engine == null) continue;
      entry.retired = true;
      entry.engine = null;
      engine.detach();
      _disposeFutures.add(engine.dispose());
    }
    final pending = [..._disposeFutures];
    _disposeFutures.clear();
    try {
      await Future.wait(pending);
    } catch (error, stack) {
      _report('multi-view engine dispose failed', error, stack);
    }
  }

  void _openTileActions(int index) {
    final selection = ref.read(multiViewSelectionProvider);
    if (index < 0 || index >= selection.channels.length) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('watch-full-screen'),
              title: const Text(
                'Watch full screen',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _watchFullScreen(index);
              },
            ),
            ListTile(
              key: const ValueKey('remove-from-multi-view'),
              title: const Text(
                'Remove from multi-view',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(multiViewSelectionProvider.notifier).remove(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(multiViewSelectionProvider);
    final visible = _visibleChannels(selection);
    return Scaffold(
      backgroundColor: Colors.black,
      body: visible.isEmpty
          ? _buildEmpty()
          : _buildGrid(selection, visible.length),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        "Add channels to multi-view from a channel's actions.",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildGrid(MultiViewSelection selection, int count) {
    final grid = multiViewGrid(count);
    final rows = <Widget>[];
    var index = 0;
    for (var row = 0; row < grid.rows; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < grid.cols; col++) {
        cells.add(
          index < count
              ? _buildTile(selection, index)
              // An empty cell in a 3-tile grid shows nothing.
              : const Expanded(child: SizedBox.expand()),
        );
        index++;
      }
      rows.add(Expanded(child: Row(children: cells)));
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Column(children: rows),
    );
  }

  Widget _buildTile(MultiViewSelection selection, int index) {
    final channel = selection.channels[index];
    final entry = _entries[channel.url];
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: MultiViewTile(
          key: ValueKey('tile-${channel.url}'),
          channelName: channel.name,
          engine: entry?.engine,
          failed: entry?.failed ?? false,
          hasAudio: index == selection.audioIndex,
          autofocus: index == 0,
          onSelected: () => _applyAudio(index),
          onLongPressed: () => _openTileActions(index),
        ),
      ),
    );
  }
}
