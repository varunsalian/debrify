import '../profiles/profile_preferences.dart';

/// Profile-scoped destination strings; OS grants remain with the callers.
class DownloadDestinationPrefs {
  DownloadDestinationPrefs._();

  static const String _downloadTreeUriKey = 'download_tree_uri_v1';
  static const String _downloadTreeNameKey = 'download_tree_display_name_v1';
  static const String _downloadDirPathKey = 'download_dir_path_v1';

  static const Set<String> ownedKeys = {
    _downloadTreeUriKey,
    _downloadTreeNameKey,
    _downloadDirPathKey,
  };

  static Future<String?> getDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeUriKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<String?> getDownloadTreeDisplayName() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeNameKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadTreeUri(
    String treeUri,
    String displayName,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadTreeUriKey, treeUri);
    await prefs.setString(_downloadTreeNameKey, displayName);
  }

  static Future<void> clearDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadTreeUriKey);
    await prefs.remove(_downloadTreeNameKey);
  }

  static Future<String?> getDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadDirPathKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadDirPath(String dirPath) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadDirPathKey, dirPath);
  }

  static Future<void> clearDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadDirPathKey);
  }
}
