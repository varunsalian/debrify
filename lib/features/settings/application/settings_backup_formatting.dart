import 'package:debrify/services/backup_restore_service.dart'
    show BackupSummary, RestoreReport;

List<String> backupSummaryLines(BackupSummary s) {
  final lines = <String>[];
  if (s.hasRealDebrid) lines.add('Real-Debrid');
  if (s.hasTorbox) lines.add('Torbox');
  if (s.hasPremiumize) lines.add('Premiumize');
  if (s.hasAllDebrid) lines.add('AllDebrid');
  if (s.hasPikpak) lines.add('PikPak');
  if (s.hasTrakt) lines.add('Trakt');
  if (s.hasSimkl) lines.add('Simkl');
  if (s.hasMdblist) lines.add('MDBList');
  if (s.searchEngineCount > 0) {
    lines.add('Search engines (${s.searchEngineCount})');
  }
  if (s.addonCount > 0) lines.add('Stremio addons (${s.addonCount})');
  if (s.webDavServerCount > 0) {
    lines.add('WebDAV servers (${s.webDavServerCount})');
  }
  if (s.indexerManagerCount > 0) {
    lines.add('Jackett/Prowlarr (${s.indexerManagerCount})');
  }
  if (s.iptvPlaylistCount > 0) {
    lines.add('IPTV providers (${s.iptvPlaylistCount})');
  }
  if (s.iptvFavoriteCount > 0) {
    lines.add('IPTV favorites (${s.iptvFavoriteCount} channels)');
  }
  if (s.iptvListCount > 0) {
    lines.add(
      'IPTV lists (${s.iptvListCount}, '
      '${s.iptvListChannelCount} channels)',
    );
  }
  if (s.homeCollectionCount > 0) {
    lines.add('Collections (${s.homeCollectionCount})');
  }
  if (s.streamBadgeSourceCount > 0) {
    lines.add('Stream badge rulesets (${s.streamBadgeSourceCount})');
  }
  return lines;
}

String formatRestoreReport(RestoreReport r) {
  final parts = <String>[];
  if (r.realDebrid) parts.add('Real-Debrid');
  if (r.torbox) parts.add('Torbox');
  if (r.premiumize) parts.add('Premiumize');
  if (r.allDebrid) parts.add('AllDebrid');
  if (r.pikpak) parts.add('PikPak');
  if (r.trakt) parts.add('Trakt');
  if (r.simkl) parts.add('Simkl');
  if (r.mdblist) parts.add('MDBList');
  if (r.searchEnginesImported > 0) {
    parts.add('${r.searchEnginesImported} new engine(s)');
  }
  if (r.addonsImported > 0) {
    parts.add('${r.addonsImported} new addon(s)');
  }
  if (r.webDavServersImported > 0) {
    parts.add('${r.webDavServersImported} WebDAV server(s)');
  }
  if (r.indexerManagersImported > 0) {
    parts.add('${r.indexerManagersImported} indexer manager(s)');
  }
  if (r.iptvPlaylistsImported > 0) {
    parts.add('${r.iptvPlaylistsImported} IPTV provider(s)');
  }
  if (r.iptvFavoritesImported > 0) {
    parts.add('${r.iptvFavoritesImported} favorite channel(s)');
  }
  if (r.iptvListsCreated > 0) {
    parts.add('${r.iptvListsCreated} IPTV list(s)');
  }
  if (r.iptvListChannelsImported > 0) {
    parts.add('${r.iptvListChannelsImported} list channel(s)');
  }
  if (r.homeCollectionsImported > 0) {
    parts.add('${r.homeCollectionsImported} collection(s)');
  }
  if (r.streamBadgeSourcesImported > 0) {
    parts.add('${r.streamBadgeSourcesImported} badge ruleset(s)');
  }

  if (parts.isEmpty && !r.hasAnyFailure) {
    return 'Nothing new to restore — everything was already present';
  }
  final base = parts.isEmpty
      ? 'Restore finished'
      : 'Restored: ${parts.join(', ')}';
  final notes = <String>[];
  if (r.searchEnginesAlreadyPresent > 0) {
    notes.add('${r.searchEnginesAlreadyPresent} engine(s) already present');
  }
  if (r.addonsAlreadyPresent > 0) {
    notes.add('${r.addonsAlreadyPresent} addon(s) already present');
  }
  if (r.webDavServersAlreadyPresent > 0) {
    notes.add(
      '${r.webDavServersAlreadyPresent} WebDAV server(s) already present',
    );
  }
  if (r.indexerManagersAlreadyPresent > 0) {
    notes.add(
      '${r.indexerManagersAlreadyPresent} indexer manager(s) already present',
    );
  }
  if (r.iptvPlaylistsAlreadyPresent > 0) {
    notes.add(
      '${r.iptvPlaylistsAlreadyPresent} IPTV provider(s) already present',
    );
  }
  if (r.iptvFavoritesAlreadyPresent > 0) {
    notes.add('${r.iptvFavoritesAlreadyPresent} favorite(s) already present');
  }
  if (r.iptvListsMerged > 0) {
    notes.add('${r.iptvListsMerged} existing list(s) topped up');
  }
  final withNotes = notes.isEmpty ? base : '$base (${notes.join(', ')})';

  if (!r.hasAnyFailure) return withNotes;
  final failed = <String>[];
  if (r.pikpakLoginFailed) {
    failed.add('PikPak login (credentials saved — retry from PikPak settings)');
  }
  if (r.searchEnginesFailed > 0) {
    failed.add('${r.searchEnginesFailed} engine(s)');
  }
  if (r.addonsFailed > 0) failed.add('${r.addonsFailed} addon(s)');
  if (r.webDavServersFailed > 0) {
    failed.add('${r.webDavServersFailed} WebDAV server(s)');
  }
  if (r.indexerManagersFailed > 0) {
    failed.add('${r.indexerManagersFailed} indexer manager(s)');
  }
  if (r.iptvPlaylistsFailed > 0) {
    failed.add('${r.iptvPlaylistsFailed} IPTV provider(s)');
  }
  if (r.iptvFavoritesFailed > 0) {
    failed.add('${r.iptvFavoritesFailed} favorite(s)');
  }
  if (r.iptvListsFailed > 0) {
    failed.add('${r.iptvListsFailed} IPTV list entr(ies)');
  }
  failed.addAll(r.errors);
  return '$withNotes — failed: ${failed.join(', ')}';
}
