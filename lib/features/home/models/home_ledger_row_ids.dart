/// Home row ids for the Ledger tracker (placeholder name). Persisted in the
/// saved Home order and the hidden-rows set, so they must not change.
abstract final class HomeLedgerRowIds {
  /// The single Ledger Continue Watching row.
  static const String continueWatching = 'ledger:continue';

  /// Never rendered (the row is always combined); reserved so the family
  /// builder has a distinct id for its unused second slot.
  static const String unusedSeries = 'ledger:shows';
}
