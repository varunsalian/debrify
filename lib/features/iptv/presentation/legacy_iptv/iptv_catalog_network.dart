import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/xtream_codes_service.dart';

typedef IptvCatalogNetworkDeps = ({
  IptvCatalogState catalogState,
  IptvSettingsState settingsState,
  bool Function() mounted,
  void Function(int ticket, String phase, {int? bytes, int? totalBytes})
  onLoadPhase,
});

class IptvCatalogNetwork {
  final IptvCatalogNetworkDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvSettingsState _settingsState;

  IptvCatalogNetwork(this._deps)
    : _catalogState = _deps.catalogState,
      _settingsState = _deps.settingsState;

  /// One network fetch for the cacheable sources, with the content type
  /// captured by the caller — a background revalidate must fetch the type it
  /// was started for even if the user has since switched tabs.
  Future<IptvParseResult> fetchCatalogFromNetwork(
    IptvPlaylist playlist,
    String contentType,
    int ticket,
  ) async {
    if (IptvCatalogDb.isOpen &&
        IptvCatalogKey.forPlaylist(playlist, contentType) != null) {
      return IptvCatalogRefreshService.instance.refreshCatalog(
        playlist,
        contentType,
        force: true,
        priority: true,
        onPhase: (phase, {bytes, totalBytes}) => _deps.onLoadPhase(
          ticket,
          phase,
          bytes: bytes,
          totalBytes: totalBytes,
        ),
      );
    }
    // Built once and shared by every branch below: a branch that forgets to
    // pass it silently loses its progress reporting, which is exactly how the
    // M3U path shipped dead.
    void report(String phase, {int? bytes, int? totalBytes}) =>
        _deps.onLoadPhase(ticket, phase, bytes: bytes, totalBytes: totalBytes);

    bool isCurrent() =>
        _deps.mounted() &&
        ticket == _catalogState.loadTicket &&
        _settingsState.selectedPlaylist?.id == playlist.id &&
        (!playlist.isXtreamCodes ||
            _catalogState.selectedContentType == contentType);

    if (playlist.isXtreamCodes) {
      final xcService = XtreamCodesService.instance;
      // `?? ''` and not `!`: isXtreamCodes only guarantees serverUrl.
      // A stored entry with no credentials used to TypeError on every page
      // open — unrecoverable without clearing app data. Empty credentials
      // fail the panel's auth instead, which lands in the normal error UI.
      // (IptvCatalogKey.forPlaylist and _updateEpgContext already treat the
      // same fields this way.)
      final username = playlist.username ?? '';
      final password = playlist.password ?? '';
      if (contentType == 'vod') {
        return xcService.fetchVodStreams(
          playlist.serverUrl!,
          username,
          password,
          onPhase: report,
          connectionResourceId: playlist.connectionResourceId,
          connectionResourceRevision: playlist.connectionResourceRevision,
          isCurrent: isCurrent,
        );
      }
      if (contentType == 'series') {
        return xcService.fetchSeriesStreams(
          playlist.serverUrl!,
          username,
          password,
          onPhase: report,
          connectionResourceId: playlist.connectionResourceId,
          connectionResourceRevision: playlist.connectionResourceRevision,
          isCurrent: isCurrent,
        );
      }
      return xcService.fetchLiveStreams(
        playlist.serverUrl!,
        username,
        password,
        numberingSourceKey: playlist.id,
        onPhase: report,
        connectionResourceId: playlist.connectionResourceId,
        connectionResourceRevision: playlist.connectionResourceRevision,
        isCurrent: isCurrent,
      );
    }
    return _settingsState.iptvService.fetchPlaylist(
      playlist.url,
      numberingSourceKey: playlist.id,
      onPhase: report,
      connectionResourceId: playlist.connectionResourceId,
      connectionResourceRevision: playlist.connectionResourceRevision,
      isCurrent: isCurrent,
    );
  }
}
