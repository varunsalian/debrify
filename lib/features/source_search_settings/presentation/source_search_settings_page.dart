// The profile's "what does a title's source search look in" page. The four
// collaborators (playlist listing, choices read/write, owner identity) are
// passed in by the settings shell, so this page never touches preferences or
// the IPTV database itself. Toggles update the in-memory choices at once and
// queue their writes: the queue replays them in tap order, and a write whose
// captured owner no longer matches the active profile is dropped (a profile
// switch happened meanwhile).
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/source_search_preferences.dart';
import 'package:flutter/material.dart';

typedef SourceSearchPlaylist = ({String id, String name});

class SourceSearchSettingsPage extends StatefulWidget {
  const SourceSearchSettingsPage({
    super.key,
    required this.loadPlaylists,
    required this.read,
    required this.write,
    required this.owner,
  });

  /// Only the playlists that are searchable (a provider, not a raw channel
  /// list) are handed to the page.
  final Future<List<SourceSearchPlaylist>> Function() loadPlaylists;

  final Future<SourceSearchChoices> Function() read;

  final Future<void> Function(SourceSearchChoices choices) write;

  /// The active profile's identity (compared with `==`). A write whose
  /// toggle happened under another owner than the current one is dropped.
  final Object? Function() owner;

  @override
  State<SourceSearchSettingsPage> createState() =>
      _SourceSearchSettingsPageState();
}

class _SourceSearchSettingsPageState extends State<SourceSearchSettingsPage> {
  /// The IPTV master toggle: the first stop for a remote or keyboard once
  /// the choices arrive (see [_placeInitialFocus]).
  final FocusNode _firstToggle = FocusNode(
    debugLabel: 'source-search-first-toggle',
  );
  bool _placedFocus = false;

  /// Captured when the user leaves the page: entries that were already
  /// queued must not be persisted afterwards.
  Object? _leftPageOwner;

  bool _loading = true;
  bool _loadFailed = false;
  List<SourceSearchPlaylist> _playlists = const [];
  SourceSearchChoices _choices = const SourceSearchChoices();

  /// Write chain: every toggle appends to it, so `widget.write` sees the
  /// choices in tap order even when a write is slow.
  Future<void> _pending = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Anything still queued belonged to this page's visit.
    _leftPageOwner = const Object();
    _firstToggle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final playlists = await widget.loadPlaylists();
      final choices = await widget.read();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playlists = playlists;
        _choices = choices;
      });
      _placeInitialFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  void _placeInitialFocus() {
    if (_placedFocus) return;
    _placedFocus = true;
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstToggle.context != null) _firstToggle.requestFocus();
    });
  }

  void _commit(SourceSearchChoices next) {
    // Snapshot the active profile at tap time. Entries are compared against
    // it when they run (see [_runPendingWrite]).
    final capturedOwner = widget.owner();
    setState(() => _choices = next);
    _pending = _pending.then((_) => _runPendingWrite(next, capturedOwner));
  }

  Future<void> _runPendingWrite(
    SourceSearchChoices next,
    Object? capturedOwner,
  ) async {
    if (_leftPageOwner != null) return;
    // `==` is the documented comparison for the owner identity.
    if (widget.owner() != capturedOwner) return;
    try {
      await widget.write(next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save search sources')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(title: 'Search sources', body: _body());
  }

  Widget _body() {
    if (_loadFailed) {
      return const Center(child: Text('Could not load search sources.'));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _content();
  }

  Widget _content() {
    final choices = _choices;
    final iptvChildren = <Widget>[
      SettingsToggleTile(
        icon: Icons.live_tv_rounded,
        title: 'Search IPTV playlists',
        subtitle: 'Movies and episodes from your IPTV providers',
        value: choices.iptv,
        focusNode: _firstToggle,
        onChanged: (on) => _commit(choices.copyWith(iptv: on)),
      ),
      if (choices.iptv && _playlists.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Text('No IPTV playlists yet.'),
        ),
      if (choices.iptv)
        for (final playlist in _playlists)
          SettingsToggleTile(
            key: ValueKey('source-search-playlist-${playlist.id}'),
            icon: Icons.play_circle_outlined,
            title: playlist.name,
            subtitle: choices.includesPlaylist(playlist.id)
                ? 'Included in search'
                : 'Left out of search',
            value: choices.includesPlaylist(playlist.id),
            onChanged: (on) =>
                _commit(choices.withPlaylist(playlist.id, included: on)),
          ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsPageHeader(
                icon: Icons.travel_explore_rounded,
                title: 'Search sources',
                subtitle: "Choose what a title's source search looks in",
              ),
              const SizedBox(height: 20),
              SettingsSection(title: 'IPTV', children: iptvChildren),
              const SizedBox(height: 20),
              SettingsSection(
                title: 'Media servers',
                children: [
                  SettingsToggleTile(
                    icon: Icons.dns_outlined,
                    title: 'Search media servers',
                    subtitle: 'Jellyfin, Emby and Plex libraries',
                    value: choices.mediaServers,
                    onChanged: (on) =>
                        _commit(choices.copyWith(mediaServers: on)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
