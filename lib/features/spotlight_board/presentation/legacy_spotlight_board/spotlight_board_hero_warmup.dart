import 'dart:async';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/utils/artwork_url.dart';
import 'package:flutter/material.dart';

class SpotlightBoardHeroWarmup {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardHeroWarmup(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  void cancelWarmups() {
    for (final cancel in _owners.hero.cancelHeroWarmups.toList()) {
      cancel();
    }
  }

  Future<bool> warmHeroImage(String url) {
    final result = Completer<bool>();
    final stream = _deps
        .heroWarmupProvider(url)
        .resolve(createLocalImageConfiguration(_deps.context()));
    Timer? timer;
    late ImageStreamListener listener;
    late VoidCallback cancel;
    void finish(bool success) {
      if (result.isCompleted) return;
      timer?.cancel();
      stream.removeListener(listener);
      _owners.hero.cancelHeroWarmups.remove(cancel);
      result.complete(success);
    }

    cancel = () => finish(false);
    listener = ImageStreamListener((image, _) {
      image.dispose();
      finish(true);
    }, onError: (_, _) => finish(false));
    _owners.hero.cancelHeroWarmups.add(cancel);
    timer = Timer(const Duration(seconds: 15), cancel);
    stream.addListener(listener);
    return result.future;
  }

  void preloadHeroes() {
    _sections.heroWarmup.cancelWarmups();
    unawaited(
      view.preloadMetadata(view.hero, (item, prefs) async {
        if (!_deps.mounted()) return;
        final selected =
            prefs.provider(MetadataCategory.backgrounds) !=
            MetadataPreferences.current;
        final url =
            highQualityArtworkUrl(item.background) ??
            (!selected && (item.imdbId ?? item.id).startsWith('tt')
                ? 'https://images.metahub.space/background/large/${item.imdbId ?? item.id}/img'
                : !selected || prefs.fallback
                ? highQualityArtworkUrl(item.poster)
                : null);
        if (url == null || url.isEmpty) return;
        final timer = Stopwatch()..start();
        final failed = !await _sections.heroWarmup.warmHeroImage(url);
        DiagnosticLog.instance.recordEvent(
          source: 'metadata',
          event: 'hero_image_warm',
          fields: {'elapsed_ms': timer.elapsedMilliseconds, 'failed': failed},
        );
      }),
    );
  }
}
