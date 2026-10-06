import 'dart:async';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';

import 'package:debrify/screens/stremio_tv/stremio_tv_filter_page.dart';

import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';

import 'package:debrify/services/storage/stremio_tv_storage.dart';

import 'package:flutter/material.dart';

class StremioTvMenuActions {
  StremioTvMenuActions(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  Future<void> openChannelFilter() async {
    final filterTree = await _owners.library.service.getFilterTree();
    final disabledBefore = await StremioTvStorage.getStremioTvDisabledFilters();
    if (!_deps.mounted()) return;

    // Full-screen DPAD-first filter page (instant push, matching the
    // channel-detail transition). The page persists before popping and
    // reports whether anything changed.
    final changed = await Navigator.of(_deps.context()).push<bool>(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => StremioTvFilterPage(
          filterTree: filterTree,
          disabledFilters: Set.of(disabledBefore),
          isTelevision: _deps.isTelevision(),
        ),
      ),
    );

    if (changed == true && _deps.mounted()) {
      _sections.library.refresh();
    }
  }

  Future<void> openLocalCatalogs() async {
    final changed = await StremioTvLocalCatalogsDialog.show(_deps.context());
    if (changed == true && _deps.mounted()) {
      _sections.library.refresh();
    }
  }

  Future<void> importFromFile() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromFile(
      _deps.context(),
    );
    if (imported && _deps.mounted()) _sections.library.refresh();
  }

  Future<void> importFromUrl() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromUrl(
      _deps.context(),
    );
    if (imported && _deps.mounted()) _sections.library.refresh();
  }

  Future<void> importFromJson() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromJson(
      _deps.context(),
    );
    if (imported && _deps.mounted()) _sections.library.refresh();
  }

  Future<void> importFromRepo() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromRepo(
      _deps.context(),
    );
    if (imported && _deps.mounted()) _sections.library.refresh();
  }

  Future<void> importFromTrakt() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromTrakt(
      _deps.context(),
    );
    if (imported && _deps.mounted()) _sections.library.refresh();
  }

  Future<void> importFromMdblist() async {
    final imported = await StremioTvLocalCatalogsDialog.importFromMdblist(
      _deps.context(),
    );
    if (imported && _deps.mounted()) _sections.library.refresh();
  }
}
