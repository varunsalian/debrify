/// "Ledger" is a PLACEHOLDER code name for Debrify's own watch tracker (the
/// service at https://debrify.garib.dev/, whose development build calls itself
/// "Debrify Sync"). Neither name is final.
///
/// TODO(ledger-rename): pick the product name before release and change
/// [kLedgerDisplayName]. Renaming the code identifiers is optional, but these
/// are PERSISTED and need a compatibility migration if renamed after any
/// build ships:
/// - `TrackingSource.ledger` / `WatchProgressSource.ledger` (stored by name in
///   tracking preferences and backups),
/// - Home row id `ledger:continue` and snapshot key
///   `episode_ledger_progress_v1`,
/// - the `ledger_*` preference and secret keys in `ledger_storage.dart`.
/// See docs/ledger-tracker.md.
library;

import 'package:flutter/foundation.dart';

/// Feature flag. While it is false Ledger is hidden: no Settings card,
/// Tracking page option, Home layout entry or sign-in, and a session stored by
/// an earlier build reads as signed out, so nothing talks to the service.
/// TODO(ledger-rename): turn on once the product name is final.
bool get kLedgerEnabled => _ledgerEnabledOverride ?? _ledgerEnabledInBuilds;

const bool _ledgerEnabledInBuilds = false;
bool? _ledgerEnabledOverride;

/// Tests turn Ledger on (true) or restore the build value (null).
@visibleForTesting
set debugLedgerEnabled(bool? enabled) => _ledgerEnabledOverride = enabled;

/// User-facing name. The only place UI text should take the name from.
const String kLedgerDisplayName = 'Ledger';

/// REST API origin. Every call goes here, including the OAuth device flow.
const String kLedgerApiBaseUrl = 'https://debrify-api.garib.dev';

/// Device-flow client identifier. The server accepts any identifier.
const String kLedgerClientId = 'debrify-app';

/// Recorded on every play the app sends ("the app or device playing").
const String kLedgerScrobbleSource = 'debrify';
