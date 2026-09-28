import 'package:flutter/material.dart';
import '../../../models/debrify_tv/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_stage_metadata.dart';
import '../models/home_playlist.dart';
import '../models/home_stremio_favorites.dart';
import 'category_tag.dart';
import 'home_art_poster.dart';
import 'home_favorite_cell.dart';
import 'home_favorite_row.dart';

/// Classic favorite rows retain lazy item/node reads and the original widget
/// stack. Playback and live-preview lifecycle remain with their existing owners.
class HomeClassicFavoriteRows {
  const HomeClassicFavoriteRows({
    required this.context,
    required this.isTelevision,
    required this.posterWidth,
    required this.captionBand,
    required this.showTitle,
    required this.nodes,
    required this.up,
    required this.down,
    required this.sidebar,
    required this.clearLive,
    required this.previewLive,
  });

  final BuildContext context;
  final bool isTelevision;
  final double posterWidth;
  final double captionBand;
  final bool Function() showTitle;
  final List<FocusNode> Function() nodes;
  final VoidCallback Function(int) up;
  final VoidCallback Function(int) down;
  final VoidCallback sidebar;
  final VoidCallback clearLive;
  final ValueChanged<IptvChannel> previewLive;

  Widget watchlist({
    required bool movies,
    required List<StremioMeta> items,
    required ValueChanged<StremioMeta> onOpen,
  }) => _row(
    title: movies ? 'Watchlist Movies' : 'Watchlist Series',
    tags: [
      CategoryTag(movies ? 'Movies' : 'Series', icon: Icons.bookmark_rounded),
    ],
    count: items.length,
    cell: (col) {
      final item = items[col];
      return _card(
        col,
        image: item.poster,
        title: item.name,
        onOpen: () => onOpen(item),
        onFocused: clearLive,
      );
    },
  );

  Widget debrify({
    required int count,
    required DebrifyTvChannel Function(int) itemAt,
    required ValueChanged<DebrifyTvChannel> onOpen,
  }) => _row(
    title: 'Debrify TV',
    tags: const [
      CategoryTag('Channels'),
      CategoryTag('Favorites', icon: Icons.star_rounded),
    ],
    count: count,
    cell: (col) {
      final channel = itemAt(col);
      final number = channel.channelNumber > 0
          ? channel.channelNumber
          : col + 1;
      return _card(
        col,
        image: null,
        title: channel.name,
        badge: '$number',
        onOpen: () => onOpen(channel),
        onFocused: clearLive,
      );
    },
  );

  Widget stremio({
    required int count,
    required HomeStremioFavorite Function(int) itemAt,
    required StremioMeta? Function(HomeStremioFavorite) nowPlaying,
    required ValueChanged<HomeStremioFavorite> onOpen,
  }) => _row(
    title: 'Stremio TV',
    tags: const [
      CategoryTag('Channels'),
      CategoryTag('Favorites', icon: Icons.star_rounded),
    ],
    count: count,
    cell: (col) {
      final channel = itemAt(col);
      final item = nowPlaying(channel);
      return _card(
        col,
        image: homeStageFirstNonEmpty(item?.poster, item?.background),
        title: channel.displayName,
        live: true,
        onOpen: () => onOpen(channel),
        onFocused: clearLive,
      );
    },
  );

  Widget iptv({
    required String title,
    required bool customList,
    required int count,
    required IptvChannel Function(int) itemAt,
    required ValueChanged<IptvChannel> onOpen,
  }) => _row(
    title: title,
    tags: customList
        ? const [
            CategoryTag('IPTV'),
            CategoryTag('List', icon: Icons.playlist_play_rounded),
          ]
        : const [
            CategoryTag('Live'),
            CategoryTag('Favorites', icon: Icons.star_rounded),
          ],
    count: count,
    cell: (col) {
      final channel = itemAt(col);
      final live = !customList || channel.isLive;
      return _card(
        col,
        image: channel.logoUrl,
        title: channel.name,
        fit: BoxFit.contain,
        onOpen: () => onOpen(channel),
        onFocused: live ? () => previewLive(channel) : clearLive,
      );
    },
  );

  Widget playlist({
    required int count,
    required HomePlaylistItem Function(int) itemAt,
    required double? Function(HomePlaylistItem) progress,
    required ValueChanged<HomePlaylistItem> onOpen,
  }) => _row(
    title: 'Playlist',
    tags: const [CategoryTag('Saved')],
    count: count,
    cell: (col) {
      final item = itemAt(col);
      return _card(
        col,
        image: item.posterUrl,
        title: item.title,
        progress: progress(item),
        onOpen: () => onOpen(item),
        onFocused: clearLive,
      );
    },
  );

  Widget _row({
    required String title,
    required List<Widget> tags,
    required int count,
    required Widget Function(int) cell,
  }) => buildHomeFavoriteRow(
    context,
    isTelevision: isTelevision,
    posterWidth: posterWidth,
    captionBand: captionBand,
    title: title,
    tags: tags,
    itemCount: count,
    cellBuilder: (col, _, _) => cell(col),
  );

  Widget _card(
    int column, {
    required String? image,
    required String title,
    required VoidCallback onOpen,
    required VoidCallback onFocused,
    BoxFit fit = BoxFit.cover,
    String? badge,
    bool live = false,
    double? progress,
  }) {
    final rowNodes = nodes();
    return HomeFavoriteCell(
      onLeftEdge: sidebar,
      isTelevision: isTelevision,
      column: column,
      rowNodes: rowNodes,
      onUp: up(column),
      onDown: down(column),
      child: HomeArtPoster(
        imageUrl: image,
        title: title,
        showTitle: showTitle(),
        imageFit: fit,
        badge: badge,
        live: live,
        progress: progress,
        isTelevision: isTelevision,
        focusNode: rowNodes[column],
        onOpen: onOpen,
        onFocused: onFocused,
      ),
    );
  }
}
