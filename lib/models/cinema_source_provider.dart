class CinemaSourceProvider {
  const CinemaSourceProvider({
    required this.id,
    required this.label,
    required this.count,
    this.failed = false,
    this.loading = false,
    this.message,
  });

  /// Null is the all-sources group. Other ids retain the search's own identity.
  final String? id;
  final String label;
  final int count;
  final bool failed;
  final bool loading;
  final String? message;
}
