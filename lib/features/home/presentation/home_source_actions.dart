import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_detail_providers.dart';
import '../models/home_catalog_session.dart';
import 'home_playback_navigation.dart';
import 'home_source_editor.dart';
import 'home_local_source_picker.dart';

typedef HomeSourceActionsDeps = ({
  BuildContext Function() context,
  HomeCatalogSession Function() session,
  String? Function(StremioMeta) imdbOf,
  Future<void> Function() refreshBindings,
  HomeLocalSourcePicker Function() localPicker,
});

/// Presents the existing source editor for the originating catalog action.
class HomeSourceActions {
  HomeSourceActions(this._ref, this._deps, this._playback);
  final WidgetRef _ref;
  final HomeSourceActionsDeps _deps;
  final HomePlaybackNavigation _playback;

  Future<void> editOrSelectSource(
    StremioMeta item, {
    bool Function()? isCurrent,
  }) async {
    bool current() =>
        _playback.catalogNavigationCurrent() && (isCurrent?.call() ?? true);
    if (!current()) return;
    await HomeSourceEditor(
      context: _deps.context(),
      item: item,
      id: _deps.imdbOf(item),
      repository: _ref.read(
        homeSourceEditingRepositoryProvider(_deps.session().owner),
      ),
      localPicker: _deps.localPicker(),
      isCurrent: current,
      refreshBindings: _deps.refreshBindings,
      showMessage: _playback.snack,
      openTorrent: (item) =>
          _playback.openSourceBinding(item, isCurrent: current),
      openKeyword: (item) =>
          _playback.openSourceBinding(item, keyword: true, isCurrent: current),
    ).open();
  }
}
