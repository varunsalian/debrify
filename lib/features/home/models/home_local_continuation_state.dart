import '../../../models/stremio_addon.dart';
import '../../../models/tracking_source.dart';
import 'home_local_continuation.dart';

/// Accepted local rows and progress settings. Artwork and focus remain in UI.
class HomeLocalContinuationState {
  const HomeLocalContinuationState.initial()
    : enabled = true,
      progressSource = WatchProgressSource.smart,
      data = const HomeLocalContinuation.empty(),
      movies = const [],
      series = const [];

  const HomeLocalContinuationState._(
    this.enabled,
    this.progressSource,
    this.data,
    this.movies,
    this.series,
  );

  final bool enabled;
  final WatchProgressSource progressSource;
  final HomeLocalContinuation data;
  final List<StremioMeta> movies;
  final List<StremioMeta> series;

  HomeLocalContinuationState copyWith({
    bool? enabled,
    WatchProgressSource? progressSource,
    HomeLocalContinuation? data,
  }) => HomeLocalContinuationState._(
    enabled ?? this.enabled,
    progressSource ?? this.progressSource,
    data ?? this.data,
    data == null
        ? movies
        : List.unmodifiable(data.items.where((m) => m.type != 'series')),
    data == null
        ? series
        : List.unmodifiable(data.items.where((m) => m.type == 'series')),
  );
}
