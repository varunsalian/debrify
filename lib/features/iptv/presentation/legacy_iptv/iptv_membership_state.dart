import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;

// Favorites — the built-in list, kept as its own set because every row's
// star icon reads it on each build.
class IptvMembershipState {
  Set<String> favoriteUrls = {};

  /// Which lists each stored channel belongs to (url → list ids). Drives the
  /// list picker's checkmarks without a per-row store round-trip.
  Map<String, Set<String>> membership = const {};

  /// Every list, Favorites first then custom lists in user order.
  List<IptvListMeta> lists = const [];

  /// Original playlistId each membership was added from, keyed by
  /// (list id, url). Toggling inside a virtual shelf must keep the channel
  /// tied to its real playlist, so deleting that playlist still sweeps it out
  /// of every list — and the same URL saved into two lists from two different
  /// providers must keep BOTH origins, or one replays under the other's
  /// credentials.
  Map<(String, String), String> favoritePlaylistIds = {};

  /// Virtual "Favorites" playlist — never persisted; pinned to the top of the
  /// picker and backed by the built-in list instead of a fetch.
  static final IptvPlaylist favoritesPlaylist = IptvPlaylist(
    id: 'iptv-favorites',
    name: 'Favorites',
    url: 'favorites://',
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Virtual "Continue watching" playlist — never persisted; backed by the
  /// watch-history store joined with the positions both players save. Sits
  /// beside Favorites so a half-watched movie is reachable without having
  /// had the foresight to star it first.
  static final IptvPlaylist continuePlaylist = IptvPlaylist(
    id: 'iptv-continue',
    name: 'Continue watching',
    url: 'continue://',
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Resume fraction (0-1) per channel URL for the loaded list — drives the
  /// bar across each poster. Only on-demand items ever have an entry.
  Map<String, double> progressByUrl = {};

  /// Playlist each Continue-watching row came from (url → id). Replaying from
  /// that shelf must keep the item tied to its real provider, so deleting the
  /// provider still sweeps it — the same reason [favoritePlaylistIds] exists.
  Map<String, String> continuePlaylistIds = {};

  /// Attribute carrying a list row's originating provider through the
  /// rebuilt channel, so both origin resolvers can be exact rather than
  /// looking a URL up in a map that can only hold one answer per URL.
  static const String kListOriginAttribute = 'list_playlist_id';
}
