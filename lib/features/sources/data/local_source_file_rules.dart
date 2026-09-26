import '../models/local_source_file.dart';

LocalVideoCandidate? matchLocalMovieFiles(
  List<LocalVideoCandidate> candidates, {
  required String title,
  String? year,
}) {
  final titleTokens = _importantTokens(title);
  if (titleTokens.isEmpty) return null;

  final titleMatches = candidates.where((candidate) {
    final normalizedName = _normalize(candidate.fileName);
    return titleTokens.every(normalizedName.contains);
  }).toList();

  if (titleMatches.isEmpty) return null;

  final normalizedYear = year?.trim();
  if (normalizedYear != null && RegExp(r'^\d{4}$').hasMatch(normalizedYear)) {
    final yearMatches = titleMatches
        .where(
          (candidate) =>
              _normalize(candidate.fileName).contains(normalizedYear),
        )
        .toList();
    if (yearMatches.isNotEmpty) {
      yearMatches.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      return yearMatches.first;
    }
  }

  titleMatches.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return titleMatches.first;
}

List<String> _importantTokens(String value) {
  const stopWords = {'a', 'an', 'and', 'of', 'the'};
  return _normalize(value)
      .split(' ')
      .where((token) => token.length > 1 && !stopWords.contains(token))
      .toSet()
      .toList();
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

int localSeriesFolderMatchScore(String folderName, String title) {
  final titleTokens = _importantTokens(title);
  if (titleTokens.isEmpty) return 0;

  final normalizedFolder = _normalize(folderName);
  if (normalizedFolder.isEmpty) return 0;
  final normalizedTitle = _normalize(title);
  final titleWithoutArticle = _withoutLeadingArticle(normalizedTitle);
  var score = titleTokens.length * 10;

  if (normalizedFolder == normalizedTitle) return score + 120;
  if (titleWithoutArticle != normalizedTitle &&
      normalizedFolder == titleWithoutArticle) {
    return score + 110;
  }
  if (normalizedTitle.length > 3 &&
      normalizedFolder.startsWith('$normalizedTitle ')) {
    return score + 80;
  }
  if (titleWithoutArticle.length > 3 &&
      titleWithoutArticle != normalizedTitle &&
      normalizedFolder.startsWith('$titleWithoutArticle ')) {
    return score + 70;
  }

  if (titleTokens.length < 2) return 0;
  final folderTokens = normalizedFolder.split(' ').toSet();
  if (!titleTokens.every(folderTokens.contains)) return 0;
  score -= (folderTokens.length - titleTokens.length).clamp(0, 20);
  return score;
}

String _withoutLeadingArticle(String normalizedTitle) {
  return normalizedTitle.replaceFirst(RegExp(r'^(the|a|an) '), '');
}

String localPathName(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final index = trimmed.lastIndexOf('/');
  return index == -1 ? trimmed : trimmed.substring(index + 1);
}

String localRelativePath(String rootPath, String filePath) {
  final root = rootPath.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
  final file = filePath.replaceAll('\\', '/');
  if (file == root) return localPathName(file);
  if (file.startsWith('$root/')) {
    return file.substring(root.length + 1);
  }
  return localPathName(filePath);
}
