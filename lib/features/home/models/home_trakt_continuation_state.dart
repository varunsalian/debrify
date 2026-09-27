import 'home_trakt_continuation.dart';

/// Accepted shelves and their loading flag; focus/artwork remain view-owned.
class HomeTraktContinuationState {
  const HomeTraktContinuationState({
    this.data = const HomeTraktContinuation.empty(),
    this.loading = false,
  });

  final HomeTraktContinuation data;
  final bool loading;

  HomeTraktContinuationState copyWith({
    HomeTraktContinuation? data,
    bool? loading,
  }) => HomeTraktContinuationState(
    data: data ?? this.data,
    loading: loading ?? this.loading,
  );
}
