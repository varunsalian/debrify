import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/home_catalog_controller.dart';
import '../application/home_catalog_continuation_controller.dart';
import '../application/home_episode_artwork_controller.dart';
import '../application/home_pikpak_only_controller.dart';
import '../application/home_bound_counts_controller.dart';
import '../application/home_post_playback_refresh_controller.dart';
import '../application/home_tracker_authentication_controller.dart';
import '../application/home_settings_refresh.dart';
import '../application/home_board_providers.dart';
import '../models/home_catalog_session.dart';
import '../models/home_catalog_state.dart';
import '../models/home_episode_artwork.dart';
import '../models/home_tracker_authentication.dart';

/// Retains the Home board's application owners for one route/session. Only the
/// catalog-continuation busy publication requests a repaint; explicit loaders
/// retain the other providers' existing publication callbacks.
class HomeBoardBindings {
  HomeBoardBindings(
    WidgetRef ref,
    HomeCatalogSession session, {
    required bool Function() isCurrent,
    required void Function() onContinuationChanged,
  }) {
    _catalog = ref.listenManual(
      homeCatalogProvider(session),
      (previous, next) {},
    );
    catalog = ref.read(homeCatalogProvider(session).notifier);
    _continuation = ref.listenManual(homeCatalogContinuationProvider(session), (
      previous,
      next,
    ) {
      if (isCurrent()) onContinuationChanged();
    });
    continuation = ref.read(homeCatalogContinuationProvider(session).notifier);
    _artwork = ref.listenManual(
      homeEpisodeArtworkProvider(session),
      (previous, next) {},
    );
    artwork = ref.read(homeEpisodeArtworkProvider(session).notifier);
    _authentication = {
      for (final tracker in HomeTracker.values)
        tracker: ref.listenManual(
          homeTrackerAuthenticationProvider((view: session, tracker: tracker)),
          (previous, next) {},
        ),
    };
    authentication = {
      for (final tracker in HomeTracker.values)
        tracker: ref.read(
          homeTrackerAuthenticationProvider((
            view: session,
            tracker: tracker,
          )).notifier,
        ),
    };
    _pikpak = ref.listenManual(
      homePikpakOnlyProvider(session),
      (previous, next) {},
    );
    pikpak = ref.read(homePikpakOnlyProvider(session).notifier);
    _boundCounts = ref.listenManual(
      homeBoundCountsProvider(session),
      (previous, next) {},
    );
    boundCounts = ref.read(homeBoundCountsProvider(session).notifier);
    _playbackRefresh = ref.listenManual(
      homePostPlaybackRefreshProvider(session),
      (previous, next) {},
    );
    playbackRefresh = ref.read(
      homePostPlaybackRefreshProvider(session).notifier,
    );
    _settings = ref.listenManual(
      homeSettingsRefreshProvider(session),
      (previous, next) {},
    );
  }

  late final ProviderSubscription<HomeCatalogState> _catalog;
  late final HomeCatalogController catalog;
  late final ProviderSubscription<bool> _continuation;
  late final HomeCatalogContinuationController continuation;
  late final ProviderSubscription<HomeEpisodeArtwork> _artwork;
  late final HomeEpisodeArtworkController artwork;
  late final ProviderSubscription<bool> _pikpak;
  late final HomePikpakOnlyController pikpak;
  late final ProviderSubscription<Map<String, int>> _boundCounts;
  late final HomeBoundCountsController boundCounts;
  late final ProviderSubscription<bool> _playbackRefresh;
  late final HomePostPlaybackRefreshController playbackRefresh;
  late final Map<HomeTracker, ProviderSubscription<bool>> _authentication;
  late final Map<HomeTracker, HomeTrackerAuthenticationController>
  authentication;
  late final ProviderSubscription<HomeSettingsRefresh> _settings;
  HomeSettingsRefresh get settings => _settings.read();

  void close() {
    _continuation.close();
    _catalog.close();
    _artwork.close();
    for (final subscription in _authentication.values) {
      subscription.close();
    }
    _pikpak.close();
    _boundCounts.close();
    _playbackRefresh.close();
    _settings.close();
  }
}
