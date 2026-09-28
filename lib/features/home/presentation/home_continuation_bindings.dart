import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/home_continuation_layout_controller.dart';
import '../application/home_local_continuation_controller.dart';
import '../application/home_trakt_continuation_controller.dart';
import '../application/home_simkl_continuation_controller.dart';
import '../application/home_mdblist_continuation_controller.dart';
import '../application/home_iptv_continuation_controller.dart';
import '../models/home_continuation_layout.dart';
import '../models/home_local_continuation_state.dart';
import '../models/home_trakt_continuation_state.dart';
import '../models/home_simkl_continuation.dart';
import '../models/home_mdblist_continuation.dart';
import '../models/home_iptv_continuation_state.dart';
import '../models/home_continuation_session.dart';
import 'home_progress_view.dart';

/// Retains the five continuation families and their shared layout preferences.
/// One route/session identity is shared exactly as before; application controllers
/// still own data. Progress views remain stable live adapters, not copied maps.
class HomeContinuationBindings {
  HomeContinuationBindings(
    WidgetRef ref,
    HomeContinuationSession session, {
    required bool initiallyLoadingTrakt,
  }) {
    _layout = ref.listenManual(
      homeContinuationLayoutProvider(session),
      (previous, next) {},
    );
    layout = ref.read(homeContinuationLayoutProvider(session).notifier);
    _local = ref.listenManual(
      homeLocalContinuationProvider(session),
      (previous, next) {},
    );
    local = ref.read(homeLocalContinuationProvider(session).notifier);
    localProgress = HomeProgressView(() => local.current.data.progress);
    final traktContinuationScope = (
      session: session,
      initiallyLoading: initiallyLoadingTrakt,
    );
    _trakt = ref.listenManual(
      homeTraktContinuationProvider(traktContinuationScope),
      (previous, next) {},
    );
    trakt = ref.read(
      homeTraktContinuationProvider(traktContinuationScope).notifier,
    );
    traktProgress = HomeProgressView(() => trakt.current.data.progress);
    _simkl = ref.listenManual(
      homeSimklContinuationProvider(session),
      (previous, next) {},
    );
    simkl = ref.read(homeSimklContinuationProvider(session).notifier);
    simklProgress = HomeProgressView(() => simkl.current.progress);
    _mdblist = ref.listenManual(
      homeMdblistContinuationProvider(session),
      (previous, next) {},
    );
    mdblist = ref.read(homeMdblistContinuationProvider(session).notifier);
    mdblistProgress = HomeProgressView(() => mdblist.current.progress);
    _iptv = ref.listenManual(
      homeIptvContinuationProvider(session),
      (previous, next) {},
    );
    iptv = ref.read(homeIptvContinuationProvider(session).notifier);
  }

  late final ProviderSubscription<HomeContinuationLayout> _layout;
  late final HomeContinuationLayoutController layout;
  late final ProviderSubscription<HomeLocalContinuationState> _local;
  late final HomeLocalContinuationController local;
  late final ProviderSubscription<HomeTraktContinuationState> _trakt;
  late final HomeTraktContinuationController trakt;
  late final ProviderSubscription<HomeSimklContinuation> _simkl;
  late final HomeSimklContinuationController simkl;
  late final ProviderSubscription<HomeMdblistContinuation> _mdblist;
  late final HomeMdblistContinuationController mdblist;
  late final ProviderSubscription<HomeIptvContinuationState> _iptv;
  late final HomeIptvContinuationController iptv;
  late final Map<String, double> localProgress;
  late final Map<String, double> traktProgress;
  late final Map<String, double> simklProgress;
  late final Map<String, double> mdblistProgress;

  // Favorites close between content and layout, preserving host teardown order.
  void closeContent() {
    _local.close();
    _iptv.close();
    _trakt.close();
    _simkl.close();
    _mdblist.close();
  }

  void closeLayout() => _layout.close();
}
