import 'package:flutter/widgets.dart';

import '../../services/series_source_service.dart';

/// Opens a cloud browser in bind-source mode and reports the picked source.
///
/// The browsers are screens (Real-Debrid / TorBox downloads, Premiumize,
/// AllDebrid, PikPak files), so the implementation lives in
/// `lib/screens/cloud/cloud_browse_select_source.dart`
/// (`CloudBrowseSelectSource.opener`). Result widgets take an instance from
/// the screen that hosts them instead of importing the screen; with none
/// supplied they offer no cloud bind options. lib/widgets never imports
/// lib/screens.
abstract interface class CloudSelectSourceOpener {
  /// Open the browser for one playback-id [provider] (`debrid`, `torbox`,
  /// `premiumize`, `alldebrid`, `pikpak`); unknown ids open nothing.
  void push(
    BuildContext context, {
    required String provider,
    required String query,
    required Future<void> Function(SeriesSource) onSourceSelected,
  });

  /// One enabled provider opens immediately; both show a picker sheet.
  void pushRdOrTorbox(
    BuildContext context, {
    required String query,
    required bool rdEnabled,
    required bool torboxEnabled,
    required Future<void> Function(SeriesSource) onSourceSelected,
  });
}
