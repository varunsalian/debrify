import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'settings_summaries.dart';

/// Canonical connection views; read current summaries and retain action tear-offs.
class SettingsConnections {
  SettingsConnections(this._summaries, this._deps);
  final SettingsSummaries _summaries;
  final ({
    Future<void> Function() openAllDebridSettings,
    Future<void> Function() openIndexerManagersSettings,
    Future<void> Function() openIptvSettings,
    Future<void> Function() openMdblistSettings,
    Future<void> Function() openMediaServerSettings,
    Future<void> Function() openPikPakSettings,
    Future<void> Function() openPremiumizeSettings,
    Future<void> Function() openRealDebridSettings,
    Future<void> Function() openSimklSettings,
    Future<void> Function() openTorboxSettings,
    Future<void> Function() openTrackingSettings,
    Future<void> Function() openTraktSettings,
    Future<void> Function() openWebDavSettings,
  })
  _deps;

  // Connection cards in canonical order (matches the phone grid rows).
  String summaryFailureStatus(String label) => 'Attention';
  String summaryFailureCaption(String label) =>
      _summaries.summaryUnavailable.contains(label)
      ? 'Unavailable; retry or sign in'
      : 'Unable to load; open the item to retry';
  ConnectionInfo get rdInfo => ConnectionInfo(
    title: 'Real Debrid',
    connected:
        !_summaries.summaryFailures.contains('Real Debrid') &&
        _summaries.realDebridConnected,
    status: _summaries.summaryFailures.contains('Real Debrid')
        ? summaryFailureStatus('Real Debrid')
        : _summaries.realDebridStatus,
    caption: _summaries.summaryFailures.contains('Real Debrid')
        ? summaryFailureCaption('Real Debrid')
        : _summaries.realDebridCaption,
    onTap: _deps.openRealDebridSettings,
  );
  ConnectionInfo get torboxInfo => ConnectionInfo(
    title: 'Torbox',
    connected:
        !_summaries.summaryFailures.contains('Torbox') &&
        _summaries.torboxConnected,
    status: _summaries.summaryFailures.contains('Torbox')
        ? summaryFailureStatus('Torbox')
        : _summaries.torboxStatus,
    caption: _summaries.summaryFailures.contains('Torbox')
        ? summaryFailureCaption('Torbox')
        : _summaries.torboxCaption,
    onTap: _deps.openTorboxSettings,
  );
  ConnectionInfo get premiumizeInfo => ConnectionInfo(
    title: 'Premiumize',
    connected:
        !_summaries.summaryFailures.contains('Premiumize') &&
        _summaries.premiumizeConnected,
    status: _summaries.summaryFailures.contains('Premiumize')
        ? summaryFailureStatus('Premiumize')
        : _summaries.premiumizeStatus,
    caption: _summaries.summaryFailures.contains('Premiumize')
        ? summaryFailureCaption('Premiumize')
        : _summaries.premiumizeCaption,
    onTap: _deps.openPremiumizeSettings,
  );
  ConnectionInfo get allDebridInfo => ConnectionInfo(
    title: 'AllDebrid',
    connected:
        !_summaries.summaryFailures.contains('AllDebrid') &&
        _summaries.allDebridConnected,
    status: _summaries.summaryFailures.contains('AllDebrid')
        ? summaryFailureStatus('AllDebrid')
        : _summaries.allDebridStatus,
    caption: _summaries.summaryFailures.contains('AllDebrid')
        ? summaryFailureCaption('AllDebrid')
        : _summaries.allDebridCaption,
    onTap: _deps.openAllDebridSettings,
  );
  ConnectionInfo get pikpakInfo => ConnectionInfo(
    title: 'PikPak',
    connected:
        !_summaries.summaryFailures.contains('PikPak') &&
        _summaries.pikpakConnected,
    status: _summaries.summaryFailures.contains('PikPak')
        ? summaryFailureStatus('PikPak')
        : _summaries.pikpakStatus,
    caption: _summaries.summaryFailures.contains('PikPak')
        ? summaryFailureCaption('PikPak')
        : _summaries.pikpakCaption,
    onTap: _deps.openPikPakSettings,
  );
  ConnectionInfo get mediaServersInfo => ConnectionInfo(
    title: 'Jellyfin & Emby',
    connected:
        !_summaries.summaryFailures.contains('Media servers') &&
        _summaries.mediaServerCount > 0,
    status: _summaries.summaryFailures.contains('Media servers')
        ? 'Unavailable'
        : _summaries.mediaServerCount > 0
        ? 'Configured'
        : 'Not configured',
    caption: _summaries.mediaServerCount > 0
        ? '${_summaries.mediaServerCount} server connections'
        : 'Play movies and episodes from your servers',
    onTap: _deps.openMediaServerSettings,
  );
  ConnectionInfo get webDavInfo => ConnectionInfo(
    title: 'WebDAV',
    connected:
        !_summaries.summaryFailures.contains('WebDAV') &&
        _summaries.webDavConnected,
    status: _summaries.summaryFailures.contains('WebDAV')
        ? summaryFailureStatus('WebDAV')
        : _summaries.webDavStatus,
    caption: _summaries.summaryFailures.contains('WebDAV')
        ? summaryFailureCaption('WebDAV')
        : _summaries.webDavCaption,
    onTap: _deps.openWebDavSettings,
  );
  ConnectionInfo get iptvInfo => ConnectionInfo(
    title: 'IPTV',
    connected: !_summaries.summaryFailures.contains('IPTV'),
    status: _summaries.summaryFailures.contains('IPTV')
        ? summaryFailureStatus('IPTV')
        : _summaries.iptvCredentialsPending
        ? 'Attention'
        : 'Active',
    caption: _summaries.summaryFailures.contains('IPTV')
        ? summaryFailureCaption('IPTV')
        : _summaries.iptvCredentialsPending
        ? 'credentials pending owner sign-in'
        : 'M3U playlist channels',
    onTap: _deps.openIptvSettings,
  );
  ConnectionInfo get traktInfo => ConnectionInfo(
    title: 'Trakt',
    connected:
        !_summaries.summaryFailures.contains('Trakt') &&
        _summaries.traktConnected,
    status: _summaries.summaryFailures.contains('Trakt')
        ? summaryFailureStatus('Trakt')
        : _summaries.traktStatus,
    caption: _summaries.summaryFailures.contains('Trakt')
        ? summaryFailureCaption('Trakt')
        : _summaries.traktCaption,
    onTap: _deps.openTraktSettings,
  );
  ConnectionInfo get simklInfo => ConnectionInfo(
    title: 'Simkl',
    connected:
        !_summaries.summaryFailures.contains('Simkl') &&
        _summaries.simklConnected,
    status: _summaries.summaryFailures.contains('Simkl')
        ? summaryFailureStatus('Simkl')
        : _summaries.simklStatus,
    caption: _summaries.summaryFailures.contains('Simkl')
        ? summaryFailureCaption('Simkl')
        : _summaries.simklCaption,
    onTap: _deps.openSimklSettings,
  );
  ConnectionInfo get mdblistInfo => ConnectionInfo(
    title: 'MDBList',
    connected:
        !_summaries.summaryFailures.contains('MDBList') &&
        _summaries.mdblistConnected,
    status: _summaries.summaryFailures.contains('MDBList')
        ? summaryFailureStatus('MDBList')
        : _summaries.mdblistStatus,
    caption: _summaries.summaryFailures.contains('MDBList')
        ? summaryFailureCaption('MDBList')
        : _summaries.mdblistCaption,
    onTap: _deps.openMdblistSettings,
  );
  ConnectionInfo get trackingInfo => ConnectionInfo(
    title: 'Tracking',
    connected: true,
    status: 'Configured',
    caption: 'Scrobble, progress source & Home ticks',
    onTap: _deps.openTrackingSettings,
  );
  ConnectionInfo get indexerManagersInfo => ConnectionInfo(
    title: 'Jackett & Prowlarr',
    connected:
        !_summaries.summaryFailures.contains('Indexer managers') &&
        _summaries.indexerManagersConfigured,
    status: _summaries.summaryFailures.contains('Indexer managers')
        ? summaryFailureStatus('Indexer managers')
        : _summaries.indexerManagersStatus,
    caption: _summaries.summaryFailures.contains('Indexer managers')
        ? summaryFailureCaption('Indexer managers')
        : _summaries.indexerManagersCaption,
    onTap: _deps.openIndexerManagersSettings,
  );
}
