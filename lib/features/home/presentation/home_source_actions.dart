import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../sources/presentation/local_source_picker_composition.dart';
import '../application/home_source_editing_dependencies.dart';
import '../models/home_catalog_session.dart';
import 'home_playback_navigation.dart';
import 'home_source_editor.dart';

typedef HomeSourceActionsDeps = ({
  BuildContext Function() context,
  HomeCatalogSession Function() session,
  String? Function(StremioMeta) imdbOf,
  Future<void> Function() refreshBindings,
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
      localPicker: _ref.read(localSourcePickerProvider),
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
