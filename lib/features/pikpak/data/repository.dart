import '../models/file.dart';
import '../models/task.dart';

/// Where the PikPak browser gets its data.
///
/// An interface, so the view model depends on a list of ten method names
/// rather than on the service that implements them. Its tests, so its tests hand it
/// a fake and never open a socket, touch SharedPreferences, or care that the
/// real implementation also owns login, captcha and token refresh.
///
/// Deliberately narrow: it is what a *file browser* needs, not everything
/// PikPak exposes. Authentication is [PikPakSession]'s business and the add
/// flow's business, not a browser's.
abstract interface class PikPakRepository {
  /// One page of a folder. [parentId] null is the drive root.
  Future<({List<PikPakFile> files, String? nextPageToken})> listFiles({
    String? parentId,
    int limit,
    String? pageToken,
  });

  /// Every file under [folderId], flattened. With [includePaths] each result
  /// carries [PikPakFile.fullPath].
  Future<List<PikPakFile>> listFilesRecursive({
    required String folderId,
    int limit,
    bool includePaths,
  });

  /// The full entry including media links — a listing entry has none, so a
  /// file has to be re-fetched before it can be played.
  Future<PikPakFile> getFileDetails(String fileId);

  /// Move to PikPak's trash, where the user can still recover it.
  Future<bool> batchTrashFiles(List<String> fileIds);

  /// Remove for good.
  Future<bool> batchDeleteFiles(List<String> fileIds);

  /// Queue a magnet or direct URL into the drive.
  Future<PikPakTask> addOfflineDownload(
    String magnetLink, {
    String? parentFolderId,
  });

  /// How an offline download is progressing. The add flow polls this until
  /// the drive entry it is filling in becomes playable.
  Future<PikPakTask> getTaskStatus(String taskId);

  /// Credentials are present. Says nothing about whether they still work.
  Future<bool> isAuthenticated();

  /// The signed-in account, for the browser's header.
  Future<String?> getEmail();

  /// Whether the folder a restricted profile is pinned to still exists. False
  /// means the user deleted it out from under us and the browser must recover
  /// rather than show an empty root.
  Future<bool> verifyRestrictedFolderExists();
}
