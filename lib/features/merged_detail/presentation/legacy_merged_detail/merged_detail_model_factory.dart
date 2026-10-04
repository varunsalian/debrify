import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailModelFactory {
  final MergedDetailDependencies _deps;
  MergedDetailModelFactory(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;

  /// Everything the alternate layouts render, rebuilt with the screen so every
  /// load, refresh and tracker round-trip reaches them unchanged.
  ///
  /// Layouts are stateless with respect to data — they own only focus, scroll
  /// The bound sources behind Showcase's Sources band.
  ///
  /// A SharedPreferences read plus a JSON decode — no network — which is what
  /// lets the band paint on open. Reloaded after the source manager closes and
  /// on playback return, or it goes stale the moment anyone binds anything.
  List<SeriesSource> boundSources = const [];

  /// Called from every path that can change a binding — the source manager,
  /// the app-action menu, and playback return. A band that only refreshes on
  /// one of the three is stale the first time someone uses another.
  Future<void> loadBoundSources() async {
    final imdb = _item.imdbId;
    if (imdb == null || imdb.isEmpty) return;
    final list = await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    setState(() => boundSources = list);
  }
}
