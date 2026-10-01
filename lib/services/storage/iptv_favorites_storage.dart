import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/iptv_media_store.dart';

final class IptvFavoritesStorage {
  const IptvFavoritesStorage._();

  // ==========================================================================
  // IPTV Channel Favorites
  // ==========================================================================

  /// Canonical comparison key for an IPTV channel URL (see
  /// [IptvMediaStore.canonicalChannelKey]).
  static String canonicalIptvChannelKey(String url) {
    return IptvMediaStore.canonicalChannelKey(url);
  }

  /// Rewrite stored favorite URLs to the current format when a fetched
  /// channel matches an existing favorite canonically but not literally
  /// (e.g. favorites saved before the Xtream /live/ URL fix). Keeps the
  /// Home favorites row playing working URLs.
  static Future<void> reconcileIptvFavoriteUrls(List<IptvChannel> channels) {
    return IptvMediaStore.reconcileFavoriteUrls(channels);
  }

  /// DB-catalog variant: the fresh URLs come from the catalog rows on a
  /// worker isolate instead of a channel list.
  static Future<void> reconcileIptvFavoriteUrlsForCatalog(String catalogKey) {
    return IptvMediaStore.reconcileFavoriteUrlsForCatalog(catalogKey);
  }

  /// Set favorite status for an IPTV channel
  static Future<void> setIptvChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelFavorited(
      channelUrl,
      isFavorited,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  // ── IPTV custom lists ────────────────────────────────────────────────────

  /// Reserved id of the built-in Favorites list.
  static const String iptvFavoritesListId = IptvMediaStore.favoritesListId;

  /// Every channel list, Favorites first then custom lists in user order.
  static Future<List<IptvListMeta>> getIptvLists() {
    return IptvMediaStore.lists();
  }

  /// Create a channel list and return its id.
  static Future<String> createIptvList(String name) {
    return IptvMediaStore.createList(name);
  }

  static Future<void> renameIptvList(String listId, String name) {
    return IptvMediaStore.renameList(listId, name);
  }

  /// Delete a custom list. The channels themselves are untouched.
  static Future<void> deleteIptvList(String listId) {
    return IptvMediaStore.deleteList(listId);
  }

  static Future<void> reorderIptvLists(List<String> orderedIds) {
    return IptvMediaStore.reorderLists(orderedIds);
  }

  /// Add or remove a channel in a list.
  static Future<void> setIptvChannelInList(
    String listId,
    String channelUrl,
    bool inList, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelInList(
      listId,
      channelUrl,
      inList,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  /// One list's channels, url → metadata.
  static Future<Map<String, Map<String, dynamic>>> getIptvListChannels(
    String listId,
  ) {
    return IptvMediaStore.listChannels(listId);
  }

  /// Persist the display order of channels inside Favorites or a custom list.
  static Future<void> reorderIptvListChannels(
    String listId,
    Iterable<String> orderedUrls,
  ) {
    return IptvMediaStore.reorderListChannels(listId, orderedUrls);
  }

  static Future<List<IptvChannelOrderEntry>> getIptvCategoryOrderEntries(
    String sourceId,
    Iterable<IptvChannel> channels,
    String group,
  ) {
    return IptvMediaStore.categoryOrderEntries(sourceId, channels, group);
  }

  static Future<void> setIptvCategoryChannelOrder(
    String sourceId,
    String group,
    Iterable<IptvChannelOrderIdentity> ordered,
  ) {
    return IptvMediaStore.setCategoryChannelOrder(sourceId, group, ordered);
  }

  static Future<List<IptvChannel>> applyIptvCategoryChannelOrders(
    String sourceId,
    List<IptvChannel> channels,
  ) {
    return IptvMediaStore.applyCategoryChannelOrders(sourceId, channels);
  }

  static Future<void> removeIptvCategoryOrdersForSource(String sourceId) {
    return IptvMediaStore.removeCategoryOrdersForSource(sourceId);
  }

  /// Which lists each stored channel belongs to, url → list ids.
  static Future<Map<String, Set<String>>> getIptvChannelMembership() {
    return IptvMediaStore.channelMembership();
  }

  /// Membership + per-(list, url) origin providers in one read (see
  /// [IptvMediaStore.membershipSnapshot]).
  static Future<
    ({
      Map<String, Set<String>> membership,
      Map<(String, String), String> origins,
    })
  >
  getIptvMembershipSnapshot() {
    return IptvMediaStore.membershipSnapshot();
  }

  /// The lists one channel belongs to, matched canonically.
  static Future<Set<String>> getIptvListsForChannel(String channelUrl) {
    return IptvMediaStore.listsForChannel(channelUrl);
  }

  /// Remove every membership belonging to a playlist, across all lists.
  static Future<void> removeIptvListChannelsByPlaylistId(String playlistId) {
    return IptvMediaStore.removeListChannelsByPlaylistId(playlistId);
  }

  /// Per-channel HTTP headers stored with a favorite (see
  /// [setIptvChannelFavorited]). JSON round-trips them as a dynamic map, and
  /// favorites saved before headers existed simply have none.
  static Map<String, String> iptvFavoriteHeaders(Map<String, dynamic> meta) {
    final raw = meta['httpHeaders'];
    if (raw is! Map) return const {};
    final headers = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) headers[key] = value.toString();
    });
    return headers;
  }

  /// Remove all IPTV favorites that belong to a specific playlist
  static Future<void> removeIptvFavoritesByPlaylistId(String playlistId) {
    return IptvMediaStore.removeFavoritesByPlaylistId(playlistId);
  }

  /// Get all favorite IPTV channel URLs with metadata
  static Future<Map<String, Map<String, dynamic>>> getIptvFavoriteChannels() {
    return IptvMediaStore.favoriteChannels();
  }

  /// Get all favorite IPTV channel URLs
  static Future<Set<String>> getIptvFavoriteChannelUrls() async {
    final favorites = await getIptvFavoriteChannels();
    return favorites.keys.toSet();
  }
}
