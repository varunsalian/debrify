import '../../../utils/torrent_coverage_detector.dart';

/// Recognize exactly one episode, never a pack, range or adjacent double.
(int, int)? singleSourceEpisode(String name) {
  final normalized = name.replaceAll(RegExp(r'[._]+'), ' ');
  final matches = RegExp(
    r's(\d{1,2})e(\d{1,3})',
    caseSensitive: false,
  ).allMatches(normalized).toList();
  if (matches.length != 1) return null; // 0, or several distinct episodes
  // Reject anything that could span more than one episode. Kept greedy on
  // purpose: a false positive here just returns null (→ normal resolve,
  // always correct), whereas MISSING a range would wrongly skip a valid
  // multi-episode binding. Covers "E01-E10", "E01 to E10", "E01 & E02",
  // "E01,E02", and the adjacent double "E01E02".
  if (RegExp(
        r'e\d{1,3}\s*(?:-|–|to|thru|through|and|&|,)\s*e?\d{1,3}',
        caseSensitive: false,
      ).hasMatch(normalized) ||
      RegExp(
        r'e\d{1,3}\s*e\d{1,3}',
        caseSensitive: false,
      ).hasMatch(normalized)) {
    return null;
  }
  // Final cross-check against the coverage classifier.
  if (TorrentCoverageDetector.detectCoverage(title: name).coverageType !=
      CoverageType.singleEpisode) {
    return null;
  }
  final m = matches.first;
  final s = int.tryParse(m.group(1)!);
  final e = int.tryParse(m.group(2)!);
  if (s == null || e == null) return null;
  return (s, e);
}
