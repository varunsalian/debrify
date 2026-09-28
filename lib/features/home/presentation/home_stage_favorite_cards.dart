import 'package:flutter/material.dart';
import '../../../models/debrify_tv/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_stage_metadata.dart';
import '../models/home_playlist.dart';
import '../models/home_stremio_favorites.dart';
import 'home_art_poster.dart';
import 'home_favorite_cell.dart';
import 'home_favorite_focus.dart';

/// Stage favorite artwork, badges and focus metadata share the original card
/// stack. Nodes/actions are borrowed; no wrapper element or state is introduced.
class HomeStageFavoriteCards {
  const HomeStageFavoriteCards({
    required this.nodes,
    required this.column,
    required this.showTitle,
    required this.onLeftEdge,
    required this.onUp,
    required this.onDown,
    required this.onFocused,
    this.onLeft,
    this.onRight,
    this.onUpHold,
    this.onDownHold,
  });

  final List<FocusNode> nodes;
  final int column;
  final bool showTitle;
  final VoidCallback onLeftEdge;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;
  final void Function(HomeFavoriteFocus, IptvChannel?) onFocused;

  Widget iptv(
    IptvChannel channel, {
    required String Function() subtitle,
    required bool previewLive,
    required VoidCallback onOpen,
  }) => _build(
    imageUrl: channel.logoUrl,
    title: channel.name,
    imageFit: BoxFit.contain,
    onOpen: onOpen,
    focus: () => HomeFavoriteFocus(
      art: channel.logoUrl,
      fit: BoxFit.contain,
      title: channel.name,
      subtitle: subtitle(),
    ),
    liveChannel: previewLive ? channel : null,
  );

  Widget watchlist(StremioMeta item, {required VoidCallback onOpen}) => _build(
    imageUrl: item.poster,
    title: item.name,
    onOpen: onOpen,
    focus: () => HomeFavoriteFocus(
      art: homeStageFirstNonEmpty(item.background, item.poster),
      title: item.name,
      subtitle: 'MY WATCHLIST · ${item.type.toUpperCase()}',
    ),
  );

  Widget debrify(DebrifyTvChannel channel, {required VoidCallback onOpen}) {
    final number = channel.channelNumber > 0
        ? channel.channelNumber
        : column + 1;
    return _build(
      imageUrl: null,
      title: channel.name,
      badge: '$number',
      onOpen: onOpen,
      focus: () => HomeFavoriteFocus(
        art: null,
        title: channel.name,
        subtitle: 'DEBRIFY TV · CHANNEL $number',
      ),
    );
  }

  Widget stremio(
    HomeStremioFavorite channel, {
    required StremioMeta? item,
    required VoidCallback onOpen,
  }) => _build(
    imageUrl: homeStageFirstNonEmpty(item?.poster, item?.background),
    title: channel.displayName,
    live: true,
    onOpen: onOpen,
    focus: () => HomeFavoriteFocus(
      // The stage prefers wide art while the card retains the poster.
      art: homeStageFirstNonEmpty(item?.background, item?.poster),
      title: channel.displayName,
      subtitle: item != null
          ? 'STREMIO TV · NOW: ${item.name}'
          : 'STREMIO TV · CHANNEL',
    ),
  );

  Widget playlist(
    HomePlaylistItem item, {
    required double? progress,
    required VoidCallback onOpen,
  }) {
    final posterUrl = item.posterUrl;
    final title = item.title;
    return _build(
      imageUrl: posterUrl,
      title: title,
      progress: progress,
      onOpen: onOpen,
      focus: () => HomeFavoriteFocus(
        art: posterUrl,
        title: title,
        subtitle: 'PLAYLIST · SAVED',
      ),
    );
  }

  Widget _build({
    required String? imageUrl,
    required String title,
    required VoidCallback onOpen,
    required HomeFavoriteFocus Function() focus,
    BoxFit imageFit = BoxFit.cover,
    String? badge,
    bool live = false,
    double? progress,
    IptvChannel? liveChannel,
  }) => HomeFavoriteCell(
    onLeftEdge: onLeftEdge,
    isTelevision: true,
    column: column,
    rowNodes: nodes,
    onUp: onUp,
    onDown: onDown,
    onLeft: onLeft,
    onRight: onRight,
    onUpHold: onUpHold,
    onDownHold: onDownHold,
    child: HomeArtPoster(
      imageUrl: imageUrl,
      title: title,
      showTitle: showTitle,
      imageFit: imageFit,
      badge: badge,
      live: live,
      progress: progress,
      isTelevision: true,
      ringColor: Colors.white,
      focusNode: nodes[column],
      onOpen: onOpen,
      onFocused: () => onFocused(focus(), liveChannel),
    ),
  );
}
