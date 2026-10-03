import 'torbox_back_navigation.dart';
import 'torbox_bulk_delete.dart';
import 'torbox_catalog_loading.dart';
import 'torbox_focus_actions.dart';
import 'torbox_selection_actions.dart';
import 'torbox_torrent_delete_actions.dart';
import 'torbox_torrent_download_action.dart';
import 'torbox_torrent_link_actions.dart';
import 'torbox_torrent_options.dart';
import 'torbox_torrent_playback.dart';
import 'torbox_torrent_playlist_actions.dart';
import 'torbox_web_create_actions.dart';
import 'torbox_web_delete_action.dart';
import 'torbox_web_file_downloads.dart';
import 'torbox_web_link_playlist_actions.dart';
import 'torbox_web_options.dart';
import 'torbox_web_playback.dart';
import 'torbox_web_zip_download.dart';

class TorboxSections {
  late final TorboxFocusActions focusActions;
  late final TorboxTorrentDownloadAction torrentDownloadAction;
  late final TorboxTorrentPlaylistActions torrentPlaylistActions;
  late final TorboxTorrentLinkActions torrentLinkActions;
  late final TorboxTorrentOptions torrentOptions;
  late final TorboxTorrentPlayback torrentPlayback;
  late final TorboxTorrentDeleteActions torrentDeleteActions;
  late final TorboxBackNavigation backNavigation;
  late final TorboxCatalogLoading catalogLoading;
  late final TorboxWebPlayback webPlayback;
  late final TorboxWebOptions webOptions;
  late final TorboxWebZipDownload webZipDownload;
  late final TorboxWebFileDownloads webFileDownloads;
  late final TorboxWebLinkPlaylistActions webLinkPlaylistActions;
  late final TorboxWebDeleteAction webDeleteAction;
  late final TorboxSelectionActions selectionActions;
  late final TorboxBulkDelete bulkDelete;
  late final TorboxWebCreateActions webCreateActions;
}
