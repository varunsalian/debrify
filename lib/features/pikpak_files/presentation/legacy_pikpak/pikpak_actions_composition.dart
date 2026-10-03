import 'pikpak_file_download.dart';
import 'pikpak_file_playback.dart';
import 'pikpak_folder_download.dart';
import 'pikpak_folder_playback.dart';
import 'pikpak_link_actions.dart';
import 'pikpak_playlist_actions.dart';
import 'pikpak_sections.dart';

void wirePikpakActionsSections(
  PikpakSections sections,
  PikpakScope scope,
  PikpakOwners owners,
) {
  sections.filePlaybackSlot = PikpakFilePlayback((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.fileDownloadSlot = PikpakFileDownload((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.folderDownloadSlot = PikpakFolderDownload((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.folderPlaybackSlot = PikpakFolderPlayback((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
    catalogState: owners.catalogState,
  ));
  sections.playlistActionsSlot = PikpakPlaylistActions((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
    catalogState: owners.catalogState,
  ));
  sections.linkActionsSlot = PikpakLinkActions((
    mounted: scope.mounted,
    context: scope.context,
    linkState: owners.linkState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    setState: scope.setState,
    navigationState: owners.navigationState,
    refreshFiles: () => sections.feedback.refreshFiles(),
  ));
}
