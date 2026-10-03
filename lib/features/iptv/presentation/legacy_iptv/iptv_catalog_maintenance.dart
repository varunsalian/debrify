import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:flutter/material.dart';

typedef IptvCatalogMaintenanceDeps = ({
  IptvCatalogState catalogState,
  void Function({required bool narrate, required bool numbersMoved})
  finishMaintenanceChip,
  bool Function() mounted,
  void Function(CatalogSnapshot snap) rebuildDbFacades,
  Future<void> Function(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket,
  )
  revalidateDbCatalog,
  bool Function(IptvPlaylist playlist, String contentType, int ticket)
  revalidateSuperseded,
  void Function(int ticket) scheduleMaintenanceChip,
});

class IptvCatalogMaintenance {
  final IptvCatalogMaintenanceDeps _deps;
  final IptvCatalogState _catalogState;

  IptvCatalogMaintenance(this._deps) : _catalogState = _deps.catalogState;

  /// refresh.
  ///
  /// Serialization is the point. Each stage is a whole-catalog job that scans
  /// rows and takes the database write lock, and firing them independently
  /// meant two workers grinding over the same 50k rows and contending for that
  /// lock on the very first upgraded open — recreating the overlapping-heavy-
  /// work condition all of this exists to remove. Ordering also saves real
  /// work: migration numbers the rows in catalog order, so the adoption that
  /// follows confirms those numbers instead of rewriting 50k of them.
  Future<void> runCatalogMaintenance(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket, {
    required bool userRequested,
  }) async {
    final refreshHours = await IptvCatalogRefreshService.getIntervalHours();
    // Let the page settle before taking the gate. Nothing on screen waits for
    // any of this, and starting whole-catalog work while the list is still
    // painting its first rows, resolving EPG and loading logos is what tips a
    // weak box over. Deliberately OUTSIDE the gate: holding it through an idle
    // wait would make a foreground load queue behind nothing happening.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;

    // Process-wide, not just within this page: a previous page's workers keep
    // running after it is gone, and two 50k scans at once is the exact
    // condition being designed out. Whether each stage is still NEEDED is
    // decided inside the gate, against the database as it is by then — a
    // pipeline queued behind one that already did the work finds nothing to do
    // and costs a few indexed reads.
    final shouldRefresh = await IptvCatalogDb.runExclusive(() async {
      if (!_deps.mounted() ||
          ticket != _catalogState.loadTicket ||
          !IptvCatalogDb.isOpen) {
        return false;
      }
      // Decided BEFORE the work so the chip can be scheduled up front, and so
      // a launch with nothing outstanding stays completely silent — this is
      // one-time work, and every subsequent launch must say nothing at all.
      final snapBefore = IptvCatalogDb.snapshot(cacheKey);
      final willNumber =
          snapBefore != null &&
          snapBefore.channelCount > 0 &&
          snapBefore.hasLiveChannels &&
          (!IptvCatalogDb.hasNumberingSource(playlist.id) ||
              snapBefore.hasUnnumberedLiveChannels) &&
          !IptvCatalogDb.adoptionRecentlyFailed(playlist.id);
      final narrate = IptvCatalogDb.hasPendingMigrations || willNumber;
      if (narrate) _deps.scheduleMaintenanceChip(ticket);

      var numbersMoved = await runPendingMigrations(cacheKey, ticket);
      if (!_deps.mounted() || ticket != _catalogState.loadTicket) {
        _deps.finishMaintenanceChip(narrate: narrate, numbersMoved: false);
        return false;
      }

      final snap = IptvCatalogDb.snapshot(cacheKey);
      if (snap == null || snap.channelCount == 0) {
        _deps.finishMaintenanceChip(
          narrate: narrate,
          numbersMoved: numbersMoved,
        );
        return false;
      }

      final needsNumbering =
          snap.hasLiveChannels &&
          (!IptvCatalogDb.hasNumberingSource(playlist.id) ||
              snap.hasUnnumberedLiveChannels) &&
          !IptvCatalogDb.adoptionRecentlyFailed(playlist.id);
      if (needsNumbering) {
        numbersMoved =
            await adoptNumbering(playlist, cacheKey, ticket) || numbersMoved;
        if (!_deps.mounted() || ticket != _catalogState.loadTicket) {
          _deps.finishMaintenanceChip(narrate: narrate, numbersMoved: false);
          return false;
        }
      }
      _deps.finishMaintenanceChip(narrate: narrate, numbersMoved: numbersMoved);

      // Re-read staleness too: the catalog may have been refreshed by the
      // pipeline this one queued behind.
      final current = IptvCatalogDb.snapshot(cacheKey) ?? snap;
      final age = DateTime.now().millisecondsSinceEpoch - current.ingestedAt;
      if (refreshHours == 0 ||
          age < Duration(hours: refreshHours).inMilliseconds) {
        return false;
      }
      return true;
    });
    // Network work must not hold the maintenance queue that profile switches
    // drain. The service pins the connection and checks ownership again inside
    // the ingest queue before launching its worker.
    if (shouldRefresh &&
        !_deps.revalidateSuperseded(playlist, contentType, ticket)) {
      await _deps.revalidateDbCatalog(playlist, contentType, cacheKey, ticket);
    }
  }

  /// Apply any pending catalog-DB upgrade in the background, then show the
  /// result. Never rethrows: a migration that fails leaves rows exactly as
  /// they were (its transaction rolls back), and the page must keep working —
  /// throwing here would strand it on the spinner forever.
  Future<bool> runPendingMigrations(String cacheKey, int ticket) async {
    try {
      final applied = await IptvCatalogDb.ensureMigrations();
      if (!applied || !_deps.mounted() || ticket != _catalogState.loadTicket) {
        return false;
      }

      // Rows presented before the backfill landed hold null numbers; re-fault
      // them so the numbers show up. Skipped entirely when this load already
      // presented after the migration, or moved on to another catalog.
      if (_catalogState.dbSnapshot?.catalogKey != cacheKey) return true;
      final fresh = IptvCatalogDb.snapshot(cacheKey);
      if (fresh != null) _deps.rebuildDbFacades(fresh);
      return true;
    } catch (e) {
      debugPrint('IptvResultsView: catalog migration failed: $e');
    }
    return false;
  }

  /// Give stored live rows durable numbers, derived on a worker from the
  /// catalog DB. Usually this creates a missing namespace; it also fills gaps
  /// when a classifier change makes an existing unnumbered row live.
  ///
  /// The path this replaces refetched the ENTIRE provider catalog just to
  /// establish the namespace — on a 50k-channel panel a full download, 50k
  /// materialized channels and a second 50k-row generation, re-run on every
  /// visit until one refresh happened to succeed. Nothing about it needed the
  /// network: the rows were already on disk.
  ///
  /// Only ever called from inside [_runCatalogMaintenance]'s exclusivity gate.
  /// A network refresh may follow after that gate is released. It must not queue any
  /// further maintenance itself — that would wait on a gate its own caller is
  /// holding.
  Future<bool> adoptNumbering(
    IptvPlaylist playlist,
    String cacheKey,
    int ticket,
  ) async {
    try {
      final corrected = await IptvCatalogDb.adoptNumbering(
        catalogKey: cacheKey,
        sourceKey: playlist.id,
      );
      if (!_deps.mounted() || ticket != _catalogState.loadTicket) return false;
      // Adoption normally confirms the numbers the v2 backfill already wrote,
      // in which case the rows on screen are correct and rebuilding them would
      // cost focus and scroll for nothing. Relinking an archived namespace or
      // filling a newly-live row is a real correction and must repaint.
      if (corrected > 0) {
        final fresh = IptvCatalogDb.snapshot(cacheKey);
        if (fresh != null) _deps.rebuildDbFacades(fresh);
        return true;
      }
    } catch (e) {
      // Backed off inside adoptNumbering; the catalog is untouched and the
      // rows keep their provisional numbers, so there is nothing to tell the
      // user about.
      debugPrint('IptvResultsView: numbering adoption failed: $e');
    }
    return false;
  }
}
