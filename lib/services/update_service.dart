import 'dart:convert';

import 'package:http/http.dart' as http;

const String _kGithubOwner = 'varunsalian';
const String _kGithubRepo = 'debrify';
const String _kReleasesPage =
    'https://github.com/$_kGithubOwner/$_kGithubRepo/releases';

/// Provides helpers to inspect GitHub releases and determine whether a newer
/// build is available for the current client.
class UpdateService {
  static const Duration _cacheDuration = Duration(minutes: 5);

  static AppRelease? _cachedRelease;
  static DateTime? _lastFetch;

  static Uri get _latestReleaseUri => Uri.https(
    'api.github.com',
    '/repos/$_kGithubOwner/$_kGithubRepo/releases/latest',
  );

  /// Fetches the latest GitHub release, caching the response briefly so that
  /// repeated checks don't exceed the API limit when triggered automatically.
  static Future<AppRelease> fetchLatestRelease({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedRelease != null &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < _cacheDuration) {
      return _cachedRelease!;
    }

    final response = await http.get(
      _latestReleaseUri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'debrify-app',
      },
    );

    if (response.statusCode != 200) {
      throw UpdateException('GitHub responded with ${response.statusCode}');
    }

    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    final release = AppRelease.fromJson(payload);
    _cachedRelease = release;
    _lastFetch = now;
    return release;
  }

  /// Checks the latest release against the provided [currentVersion] and
  /// reports whether a newer build exists.
  static Future<UpdateSummary> checkForUpdates({
    required String currentVersion,
    bool forceRefresh = false,
  }) async {
    final release = await fetchLatestRelease(forceRefresh: forceRefresh);
    final releaseVersion = AppVersion.tryParse(release.versionLabel);
    final clientVersion = AppVersion.tryParse(currentVersion);
    final bool updateAvailable;
    if (releaseVersion == null || clientVersion == null) {
      updateAvailable = false;
    } else {
      updateAvailable = releaseVersion.compareTo(clientVersion) > 0;
    }

    return UpdateSummary(
      release: release,
      updateAvailable: updateAvailable,
      currentVersionLabel: currentVersion,
      latestVersion: releaseVersion,
      currentVersion: clientVersion,
      checkedAt: DateTime.now(),
    );
  }
}

/// Result of comparing the currently installed build against the latest
/// published GitHub release.
class UpdateSummary {
  final AppRelease release;
  final bool updateAvailable;
  final String currentVersionLabel;
  final AppVersion? latestVersion;
  final AppVersion? currentVersion;
  final DateTime checkedAt;

  const UpdateSummary({
    required this.release,
    required this.updateAvailable,
    required this.currentVersionLabel,
    required this.latestVersion,
    required this.currentVersion,
    required this.checkedAt,
  });
}

class AppRelease {
  final String versionLabel;
  final String tagName;
  final String name;
  final String body;
  final Uri htmlUrl;
  final DateTime? publishedAt;
  final bool draft;
  final bool prerelease;
  final List<AppReleaseAsset> assets;

  const AppRelease({
    required this.versionLabel,
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.draft,
    required this.prerelease,
    required this.assets,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name']?.toString().trim() ?? '';
    final releaseName = json['name']?.toString().trim() ?? '';
    final publishedRaw = json['published_at']?.toString();
    final List<AppReleaseAsset> assets = [];
    final assetsJson = json['assets'];
    if (assetsJson is List) {
      for (final item in assetsJson) {
        if (item is Map<String, dynamic>) {
          assets.add(AppReleaseAsset.fromJson(item));
        }
      }
    }

    return AppRelease(
      versionLabel: tag.isNotEmpty ? tag : releaseName,
      tagName: tag,
      name: releaseName,
      body: json['body']?.toString() ?? '',
      htmlUrl:
          Uri.tryParse(json['html_url']?.toString() ?? '') ??
          Uri.parse(_kReleasesPage),
      publishedAt: publishedRaw != null
          ? DateTime.tryParse(publishedRaw)
          : null,
      draft: json['draft'] == true,
      prerelease: json['prerelease'] == true,
      assets: assets,
    );
  }

  AppReleaseAsset? get androidApkAsset {
    for (final asset in assets) {
      if (asset.isAndroidApk) return asset;
    }
    return null;
  }
}

class AppReleaseAsset {
  final String name;
  final String label;
  final Uri downloadUrl;
  final String contentType;
  final int sizeBytes;

  const AppReleaseAsset({
    required this.name,
    required this.label,
    required this.downloadUrl,
    required this.contentType,
    required this.sizeBytes,
  });

  factory AppReleaseAsset.fromJson(Map<String, dynamic> json) {
    return AppReleaseAsset(
      name: json['name']?.toString() ?? 'download',
      label: json['label']?.toString() ?? '',
      downloadUrl:
          Uri.tryParse(json['browser_download_url']?.toString() ?? '') ??
          Uri.parse(_kReleasesPage),
      contentType:
          json['content_type']?.toString() ?? 'application/octet-stream',
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isAndroidApk {
    final nameLower = name.toLowerCase();
    return nameLower.endsWith('.apk') ||
        contentType == 'application/vnd.android.package-archive';
  }
}

/// Lightweight semantic version helper so we can compare GitHub release tags
/// like `v0.3.1` against the app's `PackageInfo.version` without another
/// dependency.
class AppVersion implements Comparable<AppVersion> {
  final List<int> segments;

  const AppVersion._(this.segments);

  factory AppVersion(List<int> segments) {
    if (segments.isEmpty) {
      throw ArgumentError('segments cannot be empty');
    }
    return AppVersion._(List<int>.from(segments, growable: false));
  }

  static AppVersion? tryParse(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final matches = RegExp(r'\d+').allMatches(value);
    if (matches.isEmpty) return null;
    final parts = matches
        .map((m) => int.tryParse(m.group(0) ?? '') ?? 0)
        .toList();
    if (parts.isEmpty) return null;
    return AppVersion(parts);
  }

  @override
  int compareTo(AppVersion other) {
    final maxLength = segments.length > other.segments.length
        ? segments.length
        : other.segments.length;
    for (var i = 0; i < maxLength; i++) {
      final a = i < segments.length ? segments[i] : 0;
      final b = i < other.segments.length ? other.segments[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  @override
  String toString() => segments.join('.');
}

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => 'UpdateException: $message';
}
