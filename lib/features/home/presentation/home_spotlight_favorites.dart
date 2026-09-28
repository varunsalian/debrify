import 'package:flutter/widgets.dart';
import '../../../models/debrify_tv/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../application/home_stage_metadata.dart';
import '../models/home_playlist.dart';
import '../models/home_stremio_favorites.dart';
import 'spotlight_iptv_card_preview.dart';

/// Favorite shelves borrow nodes and actions. Channel logos use contained tiles;
/// watchlist and rotating-title artwork retain title-card orientation.
SpotlightShelf buildSpotlightIptvFavorites({
  String? id,
  required String title,
  required List<FocusNode> nodes,
  required List<IptvChannel> channels,
  required bool landscape,
  required double Function() previewVolume,
  required ValueChanged<IptvChannel> onOpen,
}) => SpotlightShelf(
  id: id,
  title: title,
  nodes: nodes,
  items: [
    for (final channel in channels)
      SpotlightCard(
        image: channel.logoUrl,
        title: channel.name,
        subtitle: 'LIVE',
        shape: landscape
            ? SpotlightCardShape.wideChannel
            : SpotlightCardShape.channel,
        onOpen: () => onOpen(channel),
        previewBuilder: channel.isLive
            ? (_) => SpotlightIptvCardPreview(
                channel: channel,
                ambientVolume: previewVolume(),
              )
            : null,
      ),
  ],
);

SpotlightShelf buildSpotlightWatchlist({
  String? id,
  required List<FocusNode> nodes,
  required List<StremioMeta> items,
  required bool movies,
  required bool landscape,
  required ValueChanged<StremioMeta> onOpen,
}) => SpotlightShelf(
  id: id,
  title: movies ? 'Watchlist Movies' : 'Watchlist Series',
  nodes: nodes,
  // Portrait art carries its title off TV; landscape needs captions. Keep the
  // subtitle too because TV still draws it as an overlay regardless of this flag.
  captions: landscape,
  items: [
    for (final item in items)
      SpotlightCard(
        image: landscape ? homeStageWideArtwork(item) : item.poster,
        fallbackImage: landscape ? item.poster : null,
        title: item.name,
        rating: item.imdbRating,
        subtitle: movies ? 'MOVIE' : 'SERIES',
        shape: landscape ? SpotlightCardShape.wide : SpotlightCardShape.poster,
        watchedImdbId: item.progressId ?? item.id,
        watchedContentType: item.type,
        onOpen: () => onOpen(item),
      ),
  ],
);

SpotlightShelf buildSpotlightPlaylists({
  String? id,
  required List<FocusNode> nodes,
  required List<HomePlaylistItem> items,
  required double? Function(HomePlaylistItem) progress,
  required ValueChanged<HomePlaylistItem> onOpen,
}) => SpotlightShelf(
  id: id,
  title: 'Playlists',
  nodes: nodes,
  items: [
    for (final item in items)
      SpotlightCard(
        image: item.posterUrl,
        title: item.title,
        progress: progress(item),
        onOpen: () => onOpen(item),
      ),
  ],
);

SpotlightShelf buildSpotlightDebrifyFavorites({
  String? id,
  required List<FocusNode> nodes,
  required List<DebrifyTvChannel> channels,
  required bool landscape,
  required ValueChanged<DebrifyTvChannel> onOpen,
}) => SpotlightShelf(
  id: id,
  title: 'Debrify TV',
  nodes: nodes,
  items: [
    for (final channel in channels)
      SpotlightCard(
        title: channel.name,
        subtitle: 'CHANNEL ${channel.channelNumber}',
        shape: landscape
            ? SpotlightCardShape.wideChannel
            : SpotlightCardShape.channel,
        onOpen: () => onOpen(channel),
      ),
  ],
);

SpotlightShelf buildSpotlightStremioFavorites({
  String? id,
  required List<FocusNode> nodes,
  required List<HomeStremioFavorite> channels,
  required bool landscape,
  required String? Function(HomeStremioFavorite, {bool landscape}) artwork,
  required StremioMeta? Function(HomeStremioFavorite) nowPlaying,
  required ValueChanged<HomeStremioFavorite> onOpen,
}) => SpotlightShelf(
  id: id,
  title: 'Stremio TV',
  nodes: nodes,
  items: [
    for (final channel in channels)
      SpotlightCard(
        image: artwork(channel, landscape: landscape),
        fallbackImage: landscape ? nowPlaying(channel)?.poster : null,
        title: channel.displayName,
        subtitle: 'STREMIO TV',
        // Rotating title art uses the title's rating and orientation, not the
        // contained station-logo treatment of the other channel families.
        rating: nowPlaying(channel)?.imdbRating,
        shape: landscape ? SpotlightCardShape.wide : SpotlightCardShape.poster,
        onOpen: () => onOpen(channel),
      ),
  ],
);
