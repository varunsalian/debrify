import 'package:flutter/material.dart';

import '../../services/cloud/cloud_provider_id.dart';
import '../../services/series_source_service.dart';
import '../../widgets/cloud/cloud_select_source_opener.dart';
import '../alldebrid/alldebrid_files_screen.dart';
import '../debrid_downloads_screen.dart';
import '../pikpak/pikpak_files_screen.dart';
import '../premiumize/premiumize_files_screen.dart';
import '../torbox/torbox_downloads_screen.dart';

/// Bind-source cloud browsers for catalog, Trakt, and aggregated search.
/// [fromPlaybackId] only — `rd` does not open Real-Debrid.
///
/// Result widgets (lib/widgets) reach this through [opener], a
/// [CloudSelectSourceOpener] their hosting screen passes in.
class CloudBrowseSelectSource {
  CloudBrowseSelectSource._();

  /// [push] / [pushRdOrTorbox] behind the widgets-layer interface.
  static const CloudSelectSourceOpener opener = _CloudBrowseSelectSourceOpener();

  /// Sheet accents. Not [CloudProviderChrome.sourceChip] (TorBox chip is blue).
  static const rdSheetAccent = Color(0xFF22C55E);
  static const torboxSheetAccent = Color(0xFF7C3AED);

  static Widget? page({
    required String provider,
    required String query,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) {
    switch (CloudProviderId.fromPlaybackId(provider)) {
      case CloudProviderId.debrid:
        return DebridDownloadsScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: (source) {
            onSourceSelected(source);
          },
        );
      case CloudProviderId.torbox:
        return TorboxDownloadsScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: (source) {
            onSourceSelected(source);
          },
        );
      case CloudProviderId.premiumize:
        return PremiumizeFilesScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case CloudProviderId.alldebrid:
        return AllDebridFilesScreen(
          isPushedRoute: true,
          initialSearchQuery: query,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case CloudProviderId.pikpak:
        return PikPakFilesScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          onSourceSelected: onSourceSelected,
        );
      case null:
        return null;
    }
  }

  static void push(
    BuildContext context, {
    required String provider,
    required String query,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) {
    final screen = page(
      provider: provider,
      query: query,
      onSourceSelected: onSourceSelected,
    );
    if (screen == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Catalog / Trakt / aggregated: one provider opens immediately; both show
  /// a sheet. Neither still shows the sheet (same as the old copies).
  static void pushRdOrTorbox(
    BuildContext context, {
    required String query,
    required bool rdEnabled,
    required bool torboxEnabled,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) {
    void open(CloudProviderId id) => push(
          context,
          provider: id.playbackId,
          query: query,
          onSourceSelected: onSourceSelected,
        );

    if (rdEnabled && !torboxEnabled) {
      open(CloudProviderId.debrid);
      return;
    }
    if (torboxEnabled && !rdEnabled) {
      open(CloudProviderId.torbox);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Provider',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: rdSheetAccent),
              title: Text(CloudProviderId.debrid.displayName),
              onTap: () {
                Navigator.of(sheetContext).pop();
                open(CloudProviderId.debrid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: torboxSheetAccent),
              title: Text(CloudProviderId.torbox.displayName),
              onTap: () {
                Navigator.of(sheetContext).pop();
                open(CloudProviderId.torbox);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CloudBrowseSelectSourceOpener implements CloudSelectSourceOpener {
  const _CloudBrowseSelectSourceOpener();

  @override
  void push(
    BuildContext context, {
    required String provider,
    required String query,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) => CloudBrowseSelectSource.push(
    context,
    provider: provider,
    query: query,
    onSourceSelected: onSourceSelected,
  );

  @override
  void pushRdOrTorbox(
    BuildContext context, {
    required String query,
    required bool rdEnabled,
    required bool torboxEnabled,
    required Future<void> Function(SeriesSource) onSourceSelected,
  }) => CloudBrowseSelectSource.pushRdOrTorbox(
    context,
    query: query,
    rdEnabled: rdEnabled,
    torboxEnabled: torboxEnabled,
    onSourceSelected: onSourceSelected,
  );
}
