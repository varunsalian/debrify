/// Result of persisting imported channels from a ZIP file.
///
/// Contains lists of successful imports and failures for user feedback.
class ZipImportPersistenceResult {
  final List<ZipImportSuccess> successes;
  final List<ZipImportSaveFailure> failures;

  const ZipImportPersistenceResult({
    required this.successes,
    required this.failures,
  });
}

/// Represents a successfully imported and saved channel.
///
/// Contains metadata about the imported channel for display to the user.
class ZipImportSuccess {
  final String sourceName;
  final String channelName;
  final int keywordCount;
  final int torrentCount;

  const ZipImportSuccess({
    required this.sourceName,
    required this.channelName,
    required this.keywordCount,
    required this.torrentCount,
  });
}

/// Represents a failure to save an imported channel.
///
/// Contains the source name, channel name, and reason for the failure.
class ZipImportSaveFailure {
  final String sourceName;
  final String channelName;
  final String reason;

  const ZipImportSaveFailure({
    required this.sourceName,
    required this.channelName,
    required this.reason,
  });
}

/// Represents a failure to parse/import from a source file.
///
/// Used for displaying import errors to the user.
class ZipImportFailureDisplay {
  final String sourceName;
  final String reason;

  const ZipImportFailureDisplay({
    required this.sourceName,
    required this.reason,
  });
}
