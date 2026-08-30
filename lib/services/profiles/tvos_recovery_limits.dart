/// Bounds shared between the tvOS recovery-envelope preference export in
/// `ProfileRegistry` and the write-time caps that keep values durable inside
/// it. They live here, outside both, because `StorageService` must derive its
/// caps from the same numbers while `ProfileRegistry` must not import it.
class TvOsRecoveryLimits {
  const TvOsRecoveryLimits._();

  /// Logical preference key of the built-in My Watchlist. Size-capped at
  /// write time so it stays under [envelopeValueBytes] and is never dropped
  /// from a checkpoint for size.
  static const String myWatchlistPreferenceKey = 'my_watchlist_v1';

  /// A single envelope value larger than this is skipped at export and
  /// refused at import.
  static const int envelopeValueBytes = 64 * 1024;

  /// Whole-envelope preference budget.
  static const int envelopeTotalBytes = 512 * 1024;

  /// Maximum preference entries the envelope carries.
  static const int envelopeMaxEntries = 4096;
}
