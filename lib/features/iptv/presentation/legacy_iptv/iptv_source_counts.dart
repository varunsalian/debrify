import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_source_stats.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

typedef IptvSourceCountsDeps = ({
  IptvRecordingState recordingState,
  IptvSettingsState settingsState,
  bool Function() mounted,
  StateSetter setState,
});

class IptvSourceCounts {
  final IptvSourceCountsDeps _deps;
  final IptvRecordingState _recordingState;
  final IptvSettingsState _settingsState;

  IptvSourceCounts(this._deps)
    : _recordingState = _deps.recordingState,
      _settingsState = _deps.settingsState;

  /// Re-read the rail's per-source counts from the catalog. Debounced: a
  /// refresh sweep across several sources lands as ONE recompute, and the
  /// reads themselves are a handful of indexed lookups.
  void recomputeSourceCounts() {
    _recordingState.sourceCountsDebounce?.cancel();
    _recordingState.sourceCountsDebounce = Timer(
      const Duration(milliseconds: 300),
      () {
        if (!_deps.mounted() || !IptvCatalogDb.isOpen) return;
        final counts = <String, int>{};
        for (final p in _settingsState.playlists) {
          if (p.isVirtual) continue;
          try {
            final stats = IptvSourceStatsLoader.read(p);
            if (stats.cached) counts[p.id] = stats.total;
          } catch (_) {}
        }
        if (!mapEquals(counts, _recordingState.sourceCounts)) {
          _deps.setState(() => _recordingState.sourceCounts = counts);
        }
      },
    );
  }
}
