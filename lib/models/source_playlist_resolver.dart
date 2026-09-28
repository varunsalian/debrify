import 'playlist_entry.dart';
import 'torrent.dart';

/// The player supplies its request lifetime; the resolver retains profile ownership.
typedef SourcePlaylistResolve =
    Future<List<PlaylistEntry>?> Function(
      Torrent source, {
      bool Function()? canContinue,
    });
