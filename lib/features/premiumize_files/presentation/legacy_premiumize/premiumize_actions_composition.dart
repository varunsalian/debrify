import 'premiumize_date_format.dart';
import 'premiumize_file_download.dart';
import 'premiumize_file_playback.dart';
import 'premiumize_folder_download.dart';
import 'premiumize_folder_playback.dart';
import 'premiumize_link_actions.dart';
import 'premiumize_playlist_actions.dart';
import 'premiumize_sections.dart';

void wirePremiumizeActionsSections(
  PremiumizeSections sections,
  PremiumizeScope scope,
  PremiumizeOwners owners,
) {
  sections.filePlaybackSlot = PremiumizeFilePlayback((
    catalogState: owners.catalogState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.folderPlaybackSlot = PremiumizeFolderPlayback((
    catalogState: owners.catalogState,
    showLoadingDialog: (String message) =>
        sections.feedback.showLoadingDialog(message),
    dismissDialog: () => sections.feedback.dismissDialog(),
    mounted: scope.mounted,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    context: scope.context,
  ));
  sections.fileDownloadSlot = PremiumizeFileDownload((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.folderDownloadSlot = PremiumizeFolderDownload((
    catalogState: owners.catalogState,
    showLoadingDialog: (String message) =>
        sections.feedback.showLoadingDialog(message),
    dismissDialog: () => sections.feedback.dismissDialog(),
    mounted: scope.mounted,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    context: scope.context,
  ));
  sections.playlistActionsSlot = PremiumizePlaylistActions((
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    catalogState: owners.catalogState,
    showLoadingDialog: (String message) =>
        sections.feedback.showLoadingDialog(message),
    dismissDialog: () => sections.feedback.dismissDialog(),
    mounted: scope.mounted,
  ));
  sections.linkActionsSlot = PremiumizeLinkActions((
    mounted: scope.mounted,
    context: scope.context,
    linkState: owners.linkState,
    showSnackBar: (String message, {bool isError = true, Duration? duration}) =>
        sections.feedback.showSnackBar(
          message,
          isError: isError,
          duration: duration,
        ),
    catalogState: owners.catalogState,
    setState: scope.setState,
    showLoadingDialog: (String message) =>
        sections.feedback.showLoadingDialog(message),
    navigationState: owners.navigationState,
    dismissDialog: () => sections.feedback.dismissDialog(),
    refresh: () => sections.catalogLoading.refresh(),
  ));
  sections.dateFormatSlot = PremiumizeDateFormat();
}
