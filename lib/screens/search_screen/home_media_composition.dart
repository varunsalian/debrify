import '../../features/home/presentation/home_board_media.dart';
import 'home_hero_composition.dart';
import '../../features/home/presentation/home_stage_favorites.dart';

typedef HomeMediaCompositionDeps = ({
  int Function() artworkWidth,
  int Function() artworkHeight,
  bool Function() isTelevision,
  bool Function(String) isAddonChannel,
});

/// Composes borrowed hero/live signals for layout renderers without retaining a snapshot.
class HomeMediaComposition {
  HomeMediaComposition(this._deps, this._hero, this._favorites);
  final HomeMediaCompositionDeps _deps;
  final HomeHeroComposition _hero;
  final HomeStageFavorites _favorites;

  int get artworkCacheWidth => _deps.artworkWidth();
  int get artworkCacheHeight => _deps.artworkHeight();

  HomeBoardMedia get media => HomeBoardMedia(
    item: _hero.heroSection.heroItem,
    enriched: _hero.heroSection.heroEnriched,
    favorite: _favorites.canvasFavFocus,
    cacheWidth: artworkCacheWidth,
    cacheHeight: artworkCacheHeight,
    trailer: _hero.heroPreview.heroTrailer,
    isTelevision: _deps.isTelevision(),
    volume: _hero.heroPreview.heroTrailerVolume,
    loading: _hero.heroPreview.heroTrailerLoading,
    takeover: _hero.heroPreview.heroTrailerTakeover,
    liveChannel: _hero.heroLive.heroLiveChannel,
    liveUrl: _hero.heroLive.heroLiveUrl,
    isAddonChannel: _deps.isAddonChannel,
    onPlayingChanged: _hero.heroPreview.onHeroTrailerPlaying,
    onLivePlaybackFailed: _hero.heroLive.onHeroLivePlaybackFailed,
  );
}
