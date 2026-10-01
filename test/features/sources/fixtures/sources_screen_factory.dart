import 'package:debrify/features/sources/application/sources_providers.dart';
import 'package:debrify/features/sources/data/service_source_search_repository.dart';
import 'package:debrify/features/sources/data/source_search_api.dart';
import 'package:debrify/features/sources/presentation/sources_screen.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exercises the real source screen with controllable engine batches.
@visibleForTesting
Widget sourcesScreenForTesting({
  required AdvancedSearchSelection selection,
  required PlaybackMeta meta,
  required LegacySourceSearchOverride search,
  SourceAddonRetry? retry,
  bool bindMode = false,
  bool forcePlayOnTap = false,
}) => ProviderScope(
  overrides: [
    sourceSearchRepositoryProvider.overrideWith(
      (ref, session) => ServiceSourceSearchRepository(
        owner: session.owner,
        searchOverride: search,
        retryAddon: retry,
      ),
    ),
  ],
  child: SourcesScreen(
    selection: selection,
    meta: meta,
    isTelevision: true,
    bindMode: bindMode,
    forcePlayOnTap: forcePlayOnTap,
  ),
);
