import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_load_status_policy.dart';
import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:flutter/material.dart';

typedef IptvStatusChipDeps = ({
  IptvCatalogState catalogState,
  IptvStatusState statusState,
  bool Function() mounted,
  // TEMP(iptv): _recomputeSourceCounts -> IptvSourceCounts.recomputeSourceCounts (step 5).
  void Function() recomputeSourceCounts,
  StateSetter setState,
});

class IptvStatusChip {
  final IptvStatusChipDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvStatusState _statusState;

  IptvStatusChip(this._deps)
    : _catalogState = _deps.catalogState,
      _statusState = _deps.statusState;

  /// Narrate the guide download — the longest single background job, and
  /// until now completely silent.
  ///
  /// Lowest chip priority on purpose: news about the channel list (a refresh,
  /// or the one-time numbering pass) always outranks news about the guide.
  /// Throttled to whole megabytes rather than every chunk, since the chip is
  /// small and a digit flickering ten times a second reads as broken.
  void onGuidePhase(int ticket, int? bytes, int? totalBytes) {
    if (!_deps.mounted() ||
        ticket != _catalogState.loadTicket ||
        bytes == null) {
      return;
    }
    final mb = bytes ~/ (1024 * 1024);
    if (mb == _statusState.lastGuideMb) return;
    _statusState.lastGuideMb = mb;
    if (mb == 0) return; // nothing worth announcing for a small guide
    final label = IptvLoadStatusPolicy.loadBytesLabel(bytes, totalBytes);
    showChip(
      CatalogChipState.updating,
      label == null ? 'Loading TV guide…' : 'Loading TV guide… $label',
      owner: ChipOwner.guide,
    );
  }

  /// Announce the one-time library preparation — but only if it lasts long
  /// enough to be worth a word. Migration is normally ~45ms, and a chip that
  /// flashes for one frame is noise, so this borrows the refresh chip's
  /// delayed-show trick.
  void scheduleMaintenanceChip(int ticket) {
    _statusState.maintenanceChipTimer?.cancel();
    _statusState.maintenanceChipTimer = Timer(
      const Duration(milliseconds: 400),
      () {
        if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
        showChip(
          CatalogChipState.updating,
          'Preparing channel numbers…',
          owner: ChipOwner.maintenance,
        );
      },
    );
  }

  /// Close out the maintenance narration.
  ///
  /// [numbersMoved] is the whole reason this exists: when numbers actually
  /// change, every row's label gains a "CH n" prefix at once, and an
  /// unexplained mutation is worse than a slow one. When nothing moved, the
  /// chip simply goes away without ever claiming something happened.
  void finishMaintenanceChip({
    required bool narrate,
    required bool numbersMoved,
  }) {
    _statusState.maintenanceChipTimer?.cancel();
    if (!narrate) return;
    if (numbersMoved) {
      showChip(
        CatalogChipState.success,
        'Channel numbers ready',
        autoHide: const Duration(milliseconds: 2200),
        owner: ChipOwner.maintenance,
      );
      return;
    }
    hideChipIfOwned(ChipOwner.maintenance);
  }

  void showChip(
    CatalogChipState state,
    String message, {
    Duration? autoHide,
    ChipOwner owner = ChipOwner.refresh,
  }) {
    if (!_deps.mounted()) return;
    // Every catalog ingestion that completes narrates a success chip — the
    // one choke point where a first-time source (or a background refresh)
    // has just written the snapshot the rail's counts read from.
    if (state == CatalogChipState.success) _deps.recomputeSourceCounts();
    // Outranked by whatever is already speaking: stay quiet rather than
    // stomping it.
    if (!IptvLoadStatusPolicy.chipClaimAllowed(
      _statusState.chipOwner.index,
      owner.index,
    )) {
      return;
    }
    _statusState.chipOwner = owner;
    _statusState.chipHideTimer?.cancel();
    _deps.setState(() {
      _statusState.chipState = state;
      _statusState.chipMessage = message;
    });
    if (autoHide != null) {
      _statusState.chipHideTimer = Timer(autoHide, () {
        if (_deps.mounted() &&
            _statusState.chipState != CatalogChipState.hidden) {
          _deps.setState(
            () => _statusState.chipState = CatalogChipState.hidden,
          );
        }
        _statusState.chipOwner = ChipOwner.none;
      });
    }
  }

  /// Clear the chip only if [owner] still holds it — a stage that has been
  /// superseded must not blank the message that replaced it.
  void hideChipIfOwned(ChipOwner owner) {
    if (_statusState.chipOwner != owner) return;
    _statusState.chipHideTimer?.cancel();
    _statusState.chipOwner = ChipOwner.none;
    if (_deps.mounted() && _statusState.chipState != CatalogChipState.hidden) {
      _deps.setState(() => _statusState.chipState = CatalogChipState.hidden);
    }
  }
}
