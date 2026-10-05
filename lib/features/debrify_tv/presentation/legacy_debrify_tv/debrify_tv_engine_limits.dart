import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/services/engine/dynamic_engine.dart';
import 'package:debrify/services/engine/engine_registry.dart';

class DebrifyTvEngineLimits {
  final DebrifyTvDependencies _deps;
  DebrifyTvEngineLimits(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  List<DynamicEngine> enabledTvKeywordEngines(EngineRegistry registry) {
    final engines = registry
        .getTvModeEngines()
        .where(
          (engine) =>
              engine.supportsKeywordSearch &&
              (_owners.settings.tvEngineStates[engine.name] ??
                  engine.tvModeConfig?.enabledDefault ??
                  false),
        )
        .toList();
    engines.sort((a, b) => a.name.compareTo(b.name));
    return engines;
  }

  int tvChannelMaxResultsForEngine(DynamicEngine engine, int totalKeywords) {
    final useSmallChannelLimit =
        totalKeywords < _owners.settings.keywordThreshold;
    final storedLimit = useSmallChannelLimit
        ? _owners.settings.tvSmallChannelMaxByEngine[engine.name]
        : _owners.settings.tvLargeChannelMaxByEngine[engine.name];
    if (storedLimit != null) {
      return storedLimit;
    }

    final tvMode = engine.tvModeConfig;
    if (tvMode == null) {
      return 50;
    }
    return useSmallChannelLimit
        ? tvMode.smallChannel.maxResults
        : tvMode.largeChannel.maxResults;
  }

  int estimatePagesPulledForEngine(DynamicEngine engine, int resultCount) {
    if (resultCount <= 0) {
      return 0;
    }

    final pagination = engine.config.pagination;
    final resultsPerPage = pagination.resultsPerPage;
    if (pagination.type == 'none' ||
        resultsPerPage == null ||
        resultsPerPage <= 0) {
      return 1;
    }

    final estimatedPages = (resultCount + resultsPerPage - 1) ~/ resultsPerPage;
    final maxPages = pagination.maxPages;
    if (maxPages != null && maxPages > 0) {
      return min(estimatedPages, maxPages);
    }
    return estimatedPages;
  }

  int _estimatePageRequestsForEngine(DynamicEngine engine, int totalKeywords) {
    final maxResults = _sections.engines.tvChannelMaxResultsForEngine(
      engine,
      totalKeywords,
    );
    final pagination = engine.config.pagination;
    final resultsPerPage = pagination.resultsPerPage;
    if (pagination.type == 'none' ||
        resultsPerPage == null ||
        resultsPerPage <= 0) {
      return 1;
    }

    final estimatedPages = max(
      1,
      (maxResults + resultsPerPage - 1) ~/ resultsPerPage,
    );
    final maxPages = pagination.maxPages;
    if (maxPages != null && maxPages > 0) {
      return min(estimatedPages, maxPages);
    }
    return estimatedPages;
  }

  Map<String, int> quickPlayMaxResultsOverrides() {
    return Map<String, int>.from(_owners.settings.tvQuickPlayMaxByEngine);
  }

  Future<Map<String, bool>> tvEngineSearchStates() async {
    final registry = EngineRegistry.instance;
    await registry.initialize();
    return <String, bool>{
      for (final engine in registry.getKeywordSearchEngines())
        engine.name:
            _owners.settings.tvEngineStates[engine.name] ??
            engine.tvModeConfig?.enabledDefault ??
            false,
    };
  }

  int estimatedWarmDurationSeconds(
    int keywordCount, {
    int? totalKeywordUniverse,
  }) {
    if (keywordCount <= 0) {
      return 0;
    }

    final int effectiveUniverse = max(1, totalKeywordUniverse ?? keywordCount);
    final enabledEngines = _sections.engines.enabledTvKeywordEngines(
      EngineRegistry.instance,
    );
    if (enabledEngines.isEmpty) {
      return 0;
    }

    final int batches = max(
      1,
      ((keywordCount + _owners.settings.channelBatchSize - 1) ~/
          _owners.settings.channelBatchSize),
    );

    final int requestWavesPerKeyword = enabledEngines.fold<int>(
      1,
      (current, engine) => max(
        current,
        _sections.engines._estimatePageRequestsForEngine(
          engine,
          effectiveUniverse,
        ),
      ),
    );
    final int estimatedMs =
        batches *
        requestWavesPerKeyword *
        DebrifyTvConstants.keywordWarmEstimateMs;

    return (estimatedMs + 999) ~/ 1000;
  }
}
