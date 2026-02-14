import 'dart:convert';

import 'package:http/http.dart' as http;

/// Parsed reference to a GitHub or GitLab repository.
class RepoRef {
  final String platform; // 'github' or 'gitlab'
  final String owner;
  final String repo;
  final String branch;
  final String path; // sub-path within the repo (empty string for root)

  const RepoRef({
    required this.platform,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.path,
  });

  /// Human-readable display URL (e.g. "github.com/user/repo").
  String get displayUrl {
    final base = '$platform.com/$owner/$repo';
    if (path.isNotEmpty) return '$base/$path';
    return base;
  }

  /// Canonical URL that can be re-parsed back into a [RepoRef].
  String get canonicalUrl {
    if (platform == 'github') {
      final treePart = path.isNotEmpty ? '/tree/$branch/$path' : '';
      return 'https://github.com/$owner/$repo$treePart';
    } else {
      final treePart = path.isNotEmpty ? '/-/tree/$branch/$path' : '';
      return 'https://gitlab.com/$owner/$repo$treePart';
    }
  }
}

/// A single file entry from a repository listing.
class RepoFileEntry {
  final String name;
  final String path;
  final String downloadUrl;

  const RepoFileEntry({
    required this.name,
    required this.path,
    required this.downloadUrl,
  });
}

/// Static utility for parsing repo URLs and fetching file listings.
class CatalogRepoService {
  CatalogRepoService._();

  static const _timeout = Duration(seconds: 15);

  /// Parse a GitHub or GitLab URL into a [RepoRef].
  /// Returns `null` if the URL is not recognised.
  static RepoRef? parseRepoUrl(String url) {
    var cleaned = url.trim();
    if (cleaned.endsWith('.git')) {
      cleaned = cleaned.substring(0, cleaned.length - 4);
    }

    final uri = Uri.tryParse(cleaned);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;

    final host = uri.host.toLowerCase();
    final segments =
        uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (host == 'github.com') {
      return _parseGitHub(segments);
    } else if (host == 'gitlab.com') {
      return _parseGitLab(segments);
    }
    return null;
  }

  static RepoRef? _parseGitHub(List<String> segments) {
    // Minimum: /owner/repo
    if (segments.length < 2) return null;
    final owner = segments[0];
    final repo = segments[1];
    var branch = 'main';
    var path = '';

    // /owner/repo/tree/branch[/path...]
    if (segments.length >= 4 && segments[2] == 'tree') {
      branch = segments[3];
      if (segments.length > 4) {
        path = segments.sublist(4).join('/');
      }
    }

    return RepoRef(
      platform: 'github',
      owner: owner,
      repo: repo,
      branch: branch,
      path: path,
    );
  }

  static RepoRef? _parseGitLab(List<String> segments) {
    // Minimum: /owner/repo
    if (segments.length < 2) return null;
    final owner = segments[0];
    final repo = segments[1];
    var branch = 'main';
    var path = '';

    // /owner/repo/-/tree/branch[/path...]
    if (segments.length >= 5 &&
        segments[2] == '-' &&
        segments[3] == 'tree') {
      branch = segments[4];
      if (segments.length > 5) {
        path = segments.sublist(5).join('/');
      }
    }

    return RepoRef(
      platform: 'gitlab',
      owner: owner,
      repo: repo,
      branch: branch,
      path: path,
    );
  }

  /// List `.json` files in the given repo path.
  static Future<List<RepoFileEntry>> listJsonFiles(RepoRef repo) async {
    if (repo.platform == 'github') {
      return _listGitHubFiles(repo);
    } else {
      return _listGitLabFiles(repo);
    }
  }

  static Future<List<RepoFileEntry>> _listGitHubFiles(RepoRef repo) async {
    final path = repo.path.isEmpty ? '' : '/${repo.path}';
    final uri = Uri.parse(
      'https://api.github.com/repos/${repo.owner}/${repo.repo}'
      '/contents$path?ref=${repo.branch}',
    );

    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('GitHub API returned ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    final files = <RepoFileEntry>[];

    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type'] != 'file') continue;
      final name = item['name'] as String? ?? '';
      if (!name.toLowerCase().endsWith('.json')) continue;

      files.add(RepoFileEntry(
        name: name,
        path: item['path'] as String? ?? name,
        downloadUrl: item['download_url'] as String? ?? '',
      ));
    }

    return files;
  }

  static Future<List<RepoFileEntry>> _listGitLabFiles(RepoRef repo) async {
    final projectId =
        Uri.encodeComponent('${repo.owner}/${repo.repo}');
    final path =
        repo.path.isEmpty ? '' : '&path=${Uri.encodeComponent(repo.path)}';
    final uri = Uri.parse(
      'https://gitlab.com/api/v4/projects/$projectId'
      '/repository/tree?ref=${repo.branch}&per_page=100$path',
    );

    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('GitLab API returned ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    final files = <RepoFileEntry>[];

    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type'] != 'blob') continue;
      final name = item['name'] as String? ?? '';
      if (!name.toLowerCase().endsWith('.json')) continue;

      final filePath = item['path'] as String? ?? name;
      final encodedPath = filePath
          .split('/')
          .map(Uri.encodeComponent)
          .join('/');
      final downloadUrl =
          'https://gitlab.com/${repo.owner}/${repo.repo}'
          '/-/raw/${repo.branch}/$encodedPath';

      files.add(RepoFileEntry(
        name: name,
        path: filePath,
        downloadUrl: downloadUrl,
      ));
    }

    return files;
  }

  /// Download the raw content of a file from its download URL.
  static Future<String> fetchFileContent(String downloadUrl) async {
    final response =
        await http.get(Uri.parse(downloadUrl)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return response.body;
  }
}
