import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_catalog_playback_readers.dart';
import '../data/home_catalog_playback_resolver.dart';
import '../models/home_catalog_session.dart';
import 'home_series_resume_dependencies.dart';
import 'home_series_resume_resolver_dependencies.dart';
import 'home_tracker_resume_dependencies.dart';

final homeCatalogPlaybackResolverProvider = Provider.autoDispose
    .family<HomeCatalogPlaybackResolver, HomeCatalogSession>(
      (ref, session) {
        return HomeCatalogPlaybackResolver(
          seriesResume: ref.watch(homeSeriesResumeResolverProvider(session)),
          signals: ref.watch(homeSeriesResumeRepositoryProvider(session.owner)),
          trackers: ref.watch(homeTrackerResumeRepositoryProvider(session)),
          readers: HomeCatalogPlaybackReaders(session.owner),
          log: debugPrint,
        );
      },
      dependencies: [
        homeSeriesResumeResolverProvider,
        homeSeriesResumeRepositoryProvider,
        homeTrackerResumeRepositoryProvider,
      ],
    );
