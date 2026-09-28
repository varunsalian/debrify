import 'package:flutter/foundation.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/youtube_resolved_streams.dart';
import 'home_favorite_focus.dart';
import 'home_hero_live_layer.dart';
import 'home_hero_trailer_layer.dart';
import 'home_stage_art.dart';

/// Shared media composition for Home layouts. All signals are borrowed; this
/// value neither subscribes nor creates players. Returning the original widgets
/// directly preserves their element ancestry and retained player state.
/// Layouts continue to decide visibility, dimensions and layer order.
class HomeBoardMedia {
  const HomeBoardMedia({
    required this.item,
    required this.enriched,
    required this.favorite,
    required this.cacheWidth,
    required this.cacheHeight,
    required this.trailer,
    required this.isTelevision,
    required this.volume,
    required this.loading,
    required this.takeover,
    required this.liveChannel,
    required this.liveUrl,
    required this.isAddonChannel,
    required this.onPlayingChanged,
    required this.onLivePlaybackFailed,
  });

  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final ValueListenable<HomeFavoriteFocus?> favorite;
  final int cacheWidth;
  final int cacheHeight;
  final ValueListenable<YoutubeResolvedStreams?> trailer;
  final bool isTelevision;
  final double volume;
  final ValueListenable<bool> loading;
  final ValueNotifier<double> takeover;
  final ValueListenable<IptvChannel?> liveChannel;
  final ValueListenable<String?> liveUrl;
  final bool Function(String) isAddonChannel;
  final ValueChanged<bool> onPlayingChanged;
  final VoidCallback onLivePlaybackFailed;

  HomeStageArt artwork() => HomeStageArt(
    item: item,
    enriched: enriched,
    fav: favorite,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
  );

  HomeHeroTrailerLayer trailerLayer(double height, {bool fullBleed = false}) =>
      HomeHeroTrailerLayer(
        trailer: trailer,
        isTelevision: isTelevision,
        heroHeight: height,
        fullBleed: fullBleed,
        volume: volume,
        loading: loading,
        onPlayingChanged: onPlayingChanged,
        takeover: takeover,
      );

  HomeHeroLiveLayer liveLayer(double height, {bool fullBleed = false}) =>
      HomeHeroLiveLayer(
        isAddonChannel: isAddonChannel,
        channel: liveChannel,
        streamUrl: liveUrl,
        heroHeight: height,
        fullBleed: fullBleed,
        volume: volume,
        onPlayingChanged: onPlayingChanged,
        onPlaybackFailed: onLivePlaybackFailed,
      );
}
