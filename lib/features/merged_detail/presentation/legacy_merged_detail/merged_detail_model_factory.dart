import 'package:debrify/services/series_source_service.dart';

class MergedDetailModelFactory {
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
}
