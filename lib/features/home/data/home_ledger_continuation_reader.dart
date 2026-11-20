import '../models/home_ledger_continuation.dart';

/// Reads the Ledger Up Next feed: null on failure (rows are retained), an
/// empty list when signed out (rows clear).
typedef HomeLedgerContinuationReader =
    Future<List<HomeLedgerContinuationItem>?> Function();
