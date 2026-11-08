// The multi-view screen: a grid of IPTV tiles, one TrailerEngine each. The
// page owns every engine's lifetime (created from initState/listenManual,
// never from build), keeps engines keyed by channel url so tiles that move
// reuse their engine, and tears engines down before handing off to the
// full-screen player so the two never compete for a decoder.
import 'dart:async';

import 'package:debrify/features/iptv_multiview/application/multi_view_selection_notifier.dart';
import 'package:debrify/features/iptv_multiview/models/channel_versions.dart';
import 'package:debrify/features/iptv_multiview/models/multi_view_selection.dart';
import 'package:debrify/features/iptv_multiview/presentation/multi_view_tile.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/trailer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the engine for one tile. [tileCount] is the number of tiles at the
/// moment the channel was added.
typedef MultiViewEngineFactory =
    Future<TrailerEngine> Function(
      IptvChannel channel, {
      required int tileCount,
    });

/// Other versions of a channel to try when it cannot play, best first.
typedef MultiViewVersions =
    Future<List<IptvChannel>> Function(IptvChannel channel);

/// Why a tile plays a version other than the channel that was added.
enum MultiViewFallback {
  /// The original is 4K and the device would not decode another 4K stream.
  fourKBusy,

  /// The original stream did not play; this is another copy of it.
  backup,
}

/// The multi-view page: black scaffold, no app bar, [multiViewGrid] tiles.
class IptvMultiViewPage extends ConsumerStatefulWidget {
  const IptvMultiViewPage({
    super.key,
    required this.engineFactory,
    this.versions,
    this.released,
    this.showBackButton = true,
  });

  final MultiViewEngineFactory engineFactory;

  /// A back button over the grid, for devices without a system Back (Mac,
  /// iPhone, iPad, desktops). TV remotes have Back and leave it off.
  final bool showBackButton;

  /// Looks up a channel's other versions when it fails; null never retries.
  final MultiViewVersions? versions;

  /// Completed once the page is gone and every engine finished disposing,
  /// so the caller can start the full player (the page pops with the
  /// chosen channel) or bring a preview back without competing for a
  /// decoder.
  final Completer<void>? released;

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

  /// True while the factory is still building this slot's engine.
  bool starting = false;

  /// The version on screen when it is not the channel that was added.
  IptvChannel? playing;
  MultiViewFallback? fallback;

  /// Versions to try, loaded on the first failure; [nextVersion] indexes it.
  List<IptvChannel>? versions;
  int nextVersion = 0;

  /// The original was 4K when the last version also failed.
  bool fourKExhausted = false;

  StreamSubscription<void>? errors;

  /// Guards against the error stream and the first frame both reporting one
  /// failure.
  bool switching = false;

  /// The stream on screen has shown a frame: a later error is a drop, not a
  /// stream the device cannot decode.
  bool rendered = false;

  /// Drops of a stream that had played; past a few, it counts as failed.
  int drops = 0;
}

class _IptvMultiViewPageState extends ConsumerState<IptvMultiViewPage> {
  /// Tile slots keyed by channel url; entries are reused when tiles move.
  final Map<String, _TileEntry> _entries = {};

  /// Dispose futures of every engine this page created. The full-screen
  /// handoff awaits them; page teardown keeps them too.
  final List<Future<void>> _disposeFutures = [];

  /// One focus node per tile url, so a removal can hand focus to the tile
  /// that takes the slot (a remote has nothing focused otherwise).
  final Map<String, FocusNode> _tileFocus = {};

  FocusNode _focusFor(String url) => _tileFocus.putIfAbsent(
    url,
    () => FocusNode(debugLabel: 'multi-view tile $url'),
  );

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
      unawaited(entry.errors?.cancel());
      final engine = entry.engine;
      if (engine == null) continue;
      entry.engine = null;
      engine.detach();
      _disposeFutures.add(engine.dispose());
    }
    for (final node in _tileFocus.values) {
      node.dispose();
    }
    final released = widget.released;
    if (released != null) {
      unawaited(
        Future.wait(
          _disposeFutures,
        ).then<void>((_) {}, onError: (_) {}).whenComplete(() {
          if (!released.isCompleted) released.complete();
        }),
      );
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

    final disposedBefore = _disposeFutures.length;
    for (final url in _entries.keys.toList()) {
      if (visibleUrls.contains(url)) continue;
      // A retired slot frees its url at once, so a channel that left and
      // came back gets a fresh engine; an in-flight factory for the old slot
      // sees it no longer owns the url and disposes what it gets.
      _retire(_entries.remove(url)!, disposeNow: false);
      // Its focus node goes once the tile unmounted (never inline: the
      // tile's own dispose still detaches from it this frame).
      final node = _tileFocus.remove(url);
      if (node != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
      }
    }
    final removals = _disposeFutures.sublist(disposedBefore);
    if (removals.isNotEmpty) unawaited(_retryFourK(visible, removals));

    _synced = selection;
    if (visible.isEmpty) return;

    final tileCount = visible.length;
    for (final channel in visible) {
      final existing = _entries[channel.url];
      // A slot switching versions, or out of versions, keeps its state.
      if (existing != null &&
          (existing.engine != null ||
              existing.starting ||
              existing.switching ||
              existing.failed)) {
        continue;
      }
      final entry = existing ?? _TileEntry(channel.name);
      _entries[channel.url] = entry;
      entry.starting = true;
      unawaited(_startEngine(channel, entry, tileCount));
    }
    // A removal can move the sound to another tile: keep volumes in step.
    for (var i = 0; i < visible.length; i++) {
      final engine = _entries[visible[i].url]?.engine;
      unawaited(
        engine?.setVolume(i == selection.audioIndex ? 100 : 0) ??
            Future<void>.value(),
      );
    }
  }

  void _retire(_TileEntry entry, {required bool disposeNow}) {
    entry.retired = true;
    unawaited(entry.errors?.cancel());
    entry.errors = null;
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
    // The slot stays keyed by the channel that was added; [entry.playing] is
    // what actually streams when a fallback is in use.
    final url = channel.url;
    final stream = entry.playing ?? channel;
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
    } catch (error) {
      entry.starting = false;
      entry.switching = false; // or the next try returns at once
      _note('engine could not be created', error);
      if (_stillShows(entry, url)) unawaited(_tryNextVersion(channel, entry));
      return;
    }
    entry.starting = false;
    // The channel left the selection (or the page went away) while the
    // factory was running: hand the engine straight back, never open it.
    if (!_stillShows(entry, url)) {
      engine.detach();
      _disposeFutures.add(engine.dispose());
      if (_entries[url] == entry) _entries.remove(url);
      return;
    }
    entry.engine = engine;
    entry.switching = false;
    entry.rendered = false;
    entry.errors = engine.errorStream.listen(
      (_) => unawaited(_onStreamError(channel, entry, engine)),
    );
    unawaited(
      engine.firstFrameRendered.then<void>((_) {
        if (identical(entry.engine, engine)) entry.rendered = true;
      }, onError: (Object _) => _tryNextVersion(channel, entry)),
    );
    try {
      await engine.open(
        videoUrl: stream.url,
        // The page owns volume: the sound tile plays at 100, every other
        // tile stays muted (initial volumes are 100/0 by contract).
        volume: isAudioTile ? 100 : 0,
        loop: false,
        httpHeaders: stream.playbackHeaders,
      );
    } catch (error) {
      _note('stream did not open', error);
      unawaited(_tryNextVersion(channel, entry));
      return;
    }
    if (!_stillShows(entry, url)) {
      _retire(entry, disposeNow: true);
      return;
    }
    // The sound may have moved while this tile was opening, and an engine
    // still opening can drop a volume change (the Android TV player ignores
    // one until its native player exists): apply the current choice now.
    unawaited(engine.setVolume(_isAudioUrl(url) ? 100 : 0));
    if (mounted) setState(() {});
  }

  /// Whether the tile for [url] is the one with sound right now.
  bool _isAudioUrl(String url) {
    final selection = ref.read(multiViewSelectionProvider);
    final channels = _visibleChannels(selection);
    if (channels.isEmpty) return false;
    return channels[selection.audioIndex % channels.length].url == url;
  }

  /// A stream that had played and then died is reopened as it is (live
  /// streams drop and come back); one that never showed a frame, or keeps
  /// dropping, moves on to the next version.
  Future<void> _onStreamError(
    IptvChannel channel,
    _TileEntry entry,
    TrailerEngine engine,
  ) async {
    if (!identical(entry.engine, engine)) return;
    if (!entry.rendered || entry.drops >= _maxDrops) {
      return _tryNextVersion(channel, entry);
    }
    entry.drops++;
    if (entry.switching || !_stillShows(entry, channel.url)) return;
    entry.switching = true;
    await _dropEngine(entry);
    if (!_stillShows(entry, channel.url)) return;
    entry.starting = true;
    setState(() {});
    final count = _visibleChannels(ref.read(multiViewSelectionProvider)).length;
    await _startEngine(channel, entry, count);
  }

  static const _maxDrops = 3;

  /// Detaches [entry]'s engine and waits until it released its decoder.
  Future<void> _dropEngine(_TileEntry entry) async {
    unawaited(entry.errors?.cancel());
    entry.errors = null;
    final engine = entry.engine;
    entry.engine = null;
    if (engine == null) return;
    engine.detach();
    final disposal = _disposeAfterFrame(engine);
    _disposeFutures.add(disposal);
    if (mounted) setState(() {});
    await disposal.then<void>((_) {}, onError: (Object _) {});
  }

  /// A tile left the grid: tiles that only lost a decoder to another 4K tile
  /// (out of versions, or showing an HD copy) try their 4K stream again once
  /// that tile's decoder is free, so "remove another 4K tile" really works.
  Future<void> _retryFourK(
    List<IptvChannel> visible,
    List<Future<void>> removals,
  ) async {
    final waiting = [
      for (final channel in visible)
        if (_entries[channel.url] case final entry?
            when entry.fourKExhausted ||
                entry.fallback == MultiViewFallback.fourKBusy)
          (channel, entry),
    ];
    if (waiting.isEmpty) return;
    await Future.wait(removals).then<void>((_) {}, onError: (Object _) {});
    for (final (channel, entry) in waiting) {
      if (!_stillShows(entry, channel.url) || entry.switching) continue;
      entry.switching = true;
      await _dropEngine(entry);
      if (!_stillShows(entry, channel.url)) continue;
      entry
        ..failed = false
        ..fourKExhausted = false
        ..playing = null
        ..fallback = null
        ..nextVersion = 0
        ..starting = true;
      setState(() {});
      final count = _visibleChannels(
        ref.read(multiViewSelectionProvider),
      ).length;
      await _startEngine(channel, entry, count);
    }
  }

  /// The stream on [entry] failed: drop its engine and play the next version
  /// of [channel] (an HD copy of a 4K channel the device cannot decode next
  /// to another, another provider's copy of a dead stream), or say why the
  /// tile cannot play once none is left.
  Future<void> _tryNextVersion(IptvChannel channel, _TileEntry entry) async {
    final url = channel.url;
    if (entry.switching || !_stillShows(entry, url)) return;
    entry.switching = true;
    // Free its decoder before the next version asks for one.
    await _dropEngine(entry);
    final lookup = widget.versions;
    if (entry.versions == null && lookup != null) {
      final found = await lookup(
        channel,
      ).then((list) => list, onError: (Object _) => const <IptvChannel>[]);
      entry.versions = found;
    }
    if (!_stillShows(entry, url)) return;
    final versions = entry.versions ?? const <IptvChannel>[];
    // "One 4K channel at a time" only when another 4K tile is on screen; a
    // lone 4K stream that fails is just a stream that did not play.
    final visible = _visibleChannels(ref.read(multiViewSelectionProvider));
    final fourKBusy =
        channelQuality(channel.name) == 3 &&
        visible.any((c) => c.url != url && channelQuality(c.name) == 3);
    if (entry.nextVersion >= versions.length) {
      setState(() {
        entry.failed = true;
        entry.switching = false;
        entry.fourKExhausted = fourKBusy;
      });
      return;
    }
    entry
      ..playing = versions[entry.nextVersion++]
      ..fallback = fourKBusy
          ? MultiViewFallback.fourKBusy
          : MultiViewFallback.backup
      ..drops = 0
      ..starting = true;
    setState(() {});
    final count = _visibleChannels(ref.read(multiViewSelectionProvider)).length;
    await _startEngine(channel, entry, count);
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

  /// A tile failing is an expected path (the next version is tried), so it
  /// is logged, not reported as an app error. The type only: stream URLs
  /// carry provider credentials.
  void _note(String what, Object error) =>
      debugPrint('Multi-view: $what (${error.runtimeType})');

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

  /// Pops with the channel: the caller starts the full player once every
  /// engine here has released its decoder (see [IptvMultiViewPage.released]).
  void _watchFullScreen(int index) {
    final selection = ref.read(multiViewSelectionProvider);
    if (index < 0 || index >= selection.channels.length || !mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop(selection.channels[index]);
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
              // A remote needs a live row the moment the sheet opens.
              autofocus: true,
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
                _removeTile(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Removes the tile and focuses the one that takes its place (the last
  /// tile when it was last), so the remote keeps a target.
  void _removeTile(int index) {
    final notifier = ref.read(multiViewSelectionProvider.notifier);
    notifier.remove(index);
    final channels = _visibleChannels(ref.read(multiViewSelectionProvider));
    if (channels.isEmpty) return;
    final next =
        channels[index < channels.length ? index : channels.length - 1];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFor(next.url).requestFocus();
    });
  }

  // --- Layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(multiViewSelectionProvider);
    final visible = _visibleChannels(selection);
    return CallbackShortcuts(
      // Escape leaves on a keyboard, as Back does on a remote.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      // Leftover focus (a removed tile, an empty page) stays inside this
      // scope, under the Escape binding, instead of the route above it.
      child: FocusScope(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              visible.isEmpty
                  ? _buildEmpty()
                  : _buildGrid(selection, visible.length),
              if (widget.showBackButton)
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: IconButton(
                        key: const ValueKey('multi-view-back'),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
          playingName: entry?.playing?.name,
          note: switch (entry?.fallback) {
            MultiViewFallback.fourKBusy =>
              'This box plays one 4K channel at a time, so this tile shows '
                  'the HD version. Watch full screen for 4K.',
            MultiViewFallback.backup =>
              "The original stream didn't play, so this tile shows another "
                  'copy of the channel.',
            null => null,
          },
          noteTag: switch (entry?.fallback) {
            MultiViewFallback.fourKBusy => 'HD version',
            MultiViewFallback.backup => 'backup copy',
            null => null,
          },
          failedMessage: (entry?.fourKExhausted ?? false)
              ? 'This box plays one 4K channel at a time, and there is no HD '
                    'version of this channel. Watch it full screen, or remove '
                    'another 4K tile.'
              : "Can't play this channel",
          hasAudio: index == selection.audioIndex,
          autofocus: index == 0,
          focusNode: _focusFor(channel.url),
          // The first tile's note starts below the back button.
          noteTop: index == 0 && widget.showBackButton ? 64 : 8,
          // Select always gives this tile the sound (on the sound tile it
          // re-applies the volumes); holding OK, the Menu key, a long press or
          // a right click opens its actions.
          onSelected: () => _applyAudio(index),
          onLongPressed: () => _openTileActions(index),
        ),
      ),
    );
  }
}
