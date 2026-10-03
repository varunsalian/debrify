import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_load_status_policy.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/services/iptv_load_phase.dart';
import 'package:flutter/material.dart';

typedef IptvLoadStatusDeps = ({
  IptvCatalogState catalogState,
  IptvStatusState statusState,
  BuildContext Function() context,
  bool Function() mounted,
  StateSetter setState,
});

class IptvLoadStatus {
  final IptvLoadStatusDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvStatusState _statusState;

  IptvLoadStatus(this._deps)
    : _catalogState = _deps.catalogState,
      _statusState = _deps.statusState;

  /// The blocking-load state. A bare spinner is indistinguishable from a hung
  /// app, and on a 50k panel this screen is held for several seconds — so it
  /// says which stage is running, carries a real number when one exists, and
  /// runs a clock so there is always something moving even when the stage
  /// itself is opaque (a buffered download, or the decode/ingest worker).
  Widget buildLoadingState(BuildContext context) {
    final theme = Theme.of(_deps.context());
    final phase = _statusState.loadPhase;
    final startedAt = _statusState.loadStartedAt;
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);

    final step = phase == null ? -1 : IptvLoadPhases.ordered.indexOf(phase);
    final stepLabel = step < 0
        ? null
        : 'Step ${step + 1} of ${IptvLoadPhases.ordered.length}';

    final meta = <String>[
      if (loadBytesLabel != null) loadBytesLabel!,
      if (elapsed.inSeconds > 0)
        IptvLoadStatusPolicy.formatLoadElapsed(elapsed),
    ].join('  ·  ');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              phase ?? 'Loading…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (stepLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                stepLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meta,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            // Only after the wait is genuinely long: saying this immediately
            // would make every quick load look slow.
            if (elapsed >= IptvStatusState.slowLoadHint) ...[
              const SizedBox(height: 14),
              Text(
                'Large playlists can take a minute on TV devices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Begin (or restart) the blocking-load status for a fresh load.
  void beginLoadStatus() {
    _statusState.loadPhase = null;
    _statusState.loadBytes = null;
    _statusState.loadTotalBytes = null;
    _statusState.loadStartedAt = DateTime.now();
    _statusState.lastGuideMb = -1;
    _statusState.loadTicker?.cancel();
    // One repaint a second: enough for a clock and a byte counter to look
    // alive, cheap enough that a TV never notices it.
    _statusState.loadTicker = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!_deps.mounted() || !_catalogState.isLoading) {
        timer.cancel();
        return;
      }
      _deps.setState(() {});
    });
  }

  void endLoadStatus() {
    _statusState.loadTicker?.cancel();
    _statusState.loadTicker = null;
  }

  /// Receives phase reports from the services. A changed PHASE repaints
  /// immediately (four times a load); byte updates only update the fields and
  /// ride the next tick.
  void onLoadPhase(int ticket, String phase, {int? bytes, int? totalBytes}) {
    // A superseded load's fetch keeps running to completion; its reports must
    // not relabel the load that replaced it.
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
    // Only a BLOCKING load owns this display. A background revalidate runs the
    // same fetch under the same ticket, and its progress belongs in the status
    // chip, not in state the next spinner would inherit.
    if (!_catalogState.isLoading) return;
    final phaseChanged = phase != _statusState.loadPhase;
    _statusState.loadPhase = phase;
    _statusState.loadBytes = bytes;
    _statusState.loadTotalBytes = totalBytes;
    if (phaseChanged && _catalogState.isLoading) _deps.setState(() {});
  }

  String? get loadBytesLabel => IptvLoadStatusPolicy.loadBytesLabel(
    _statusState.loadBytes,
    _statusState.loadTotalBytes,
  );
}
