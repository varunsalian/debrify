/// Provider failover policy for Stremio TV.
///
/// An explicitly selected provider remains strict. `auto` tries every
/// configured provider in priority order until one returns a playable result.
class StremioTvDebridFallback {
  StremioTvDebridFallback._();

  static const List<String> autoOrder = <String>[
    'realdebrid',
    'torbox',
    'pikpak',
    'premiumize',
    'alldebrid',
  ];

  static List<String> orderFor(String selected) =>
      selected == 'auto' ? autoOrder : <String>[selected];

  /// Creates a lazy async loader whose first future is reused by every caller.
  static Future<T> Function() memoizeAsync<T>(Future<T> Function() loader) {
    Future<T>? cached;
    return () => cached ??= loader();
  }

  /// Returns the PikPak item that owns a prepared result. Folder packs must
  /// clean up the root folder, while direct results own their single file.
  static String? pikPakCleanupRootId(Map<String, dynamic> prepared) {
    final folderId = prepared['pikpakFolderId']?.toString().trim();
    if (folderId?.isNotEmpty == true) return folderId;

    final fileId = prepared['pikpakFileId']?.toString().trim();
    return fileId?.isNotEmpty == true ? fileId : null;
  }

  static Future<T?> resolve<T>({
    required String selected,
    required Future<T?> Function(String provider) attempt,
    Future<bool> Function(String provider)? canAttempt,
    bool Function()? isCancelled,
  }) async {
    for (final provider in orderFor(selected)) {
      if (isCancelled?.call() ?? false) return null;
      if (canAttempt != null) {
        final allowed = await canAttempt(provider);
        if (isCancelled?.call() ?? false) return null;
        if (!allowed) continue;
      }

      if (isCancelled?.call() ?? false) return null;
      final result = await attempt(provider);
      if (isCancelled?.call() ?? false) return null;
      if (result != null) return result;
    }
    return null;
  }
}
