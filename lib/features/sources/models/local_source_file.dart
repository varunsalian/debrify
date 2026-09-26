import 'dart:io';

typedef LocalSeriesFolderLookup = ({
  Directory? direct,
  List<LocalSeriesFolderCandidate> candidates,
});

class LocalSeriesFolderCandidate {
  final Directory directory;
  final String folderName;
  final int score;

  const LocalSeriesFolderCandidate({
    required this.directory,
    required this.folderName,
    required this.score,
  });
}

class LocalVideoCandidate {
  final File file;
  final String fileName;
  final int sizeBytes;
  final int modifiedAt;

  const LocalVideoCandidate({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}

class LocalSeriesEpisodeFile {
  final File file;
  final String relativePath;
  final String fileName;
  final int season;
  final int episode;
  final int sizeBytes;
  final int modifiedAt;

  const LocalSeriesEpisodeFile({
    required this.file,
    required this.relativePath,
    required this.fileName,
    required this.season,
    required this.episode,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}
