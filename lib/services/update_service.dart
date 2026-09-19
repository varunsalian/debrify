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

  static final Map<bool, AppRelease> _cachedReleases = {};
  static final Map<bool, DateTime> _lastFetches = {};

  static Uri get _latestReleaseUri => Uri.https(
    'api.github.com',
    '/repos/$_kGithubOwner/$_kGithubRepo/releases/latest',
  );

  static Uri get _releasesUri => Uri.https(
    'api.github.com',
    '/repos/$_kGithubOwner/$_kGithubRepo/releases',
    const {'per_page': '30'},
  );

  /// Fetches the latest GitHub release, caching the response briefly so that
  /// repeated checks don't exceed the API limit when triggered automatically.
  static Future<AppRelease> fetchLatestRelease({
    bool forceRefresh = false,
    bool includePrereleases = false,
    http.Client? client,
  }) async {
    final now = DateTime.now();
    final cachedRelease = _cachedReleases[includePrereleases];
    final lastFetch = _lastFetches[includePrereleases];
    if (!forceRefresh &&
        cachedRelease != null &&
        lastFetch != null &&
        now.difference(lastFetch) < _cacheDuration) {
      return cachedRelease;
    }

    final response = await (client?.get ?? http.get)(
      includePrereleases ? _releasesUri : _latestReleaseUri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'debrify-app',
      },
    );

    if (response.statusCode != 200) {
      throw UpdateException('GitHub responded with ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final AppRelease release;
    if (includePrereleases) {
      if (decoded is! List) {
        throw const UpdateException('GitHub returned an invalid release list');
      }
      final releases = decoded.whereType<Map<String, dynamic>>().map(
        AppRelease.fromJson,
      );
      final selected = latestEligibleRelease(releases);
      if (selected == null) {
        throw const UpdateException('No published releases were found');
      }
      release = selected;
    } else {
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateException('GitHub returned an invalid release');
      }
      release = AppRelease.fromJson(decoded);
    }
    _cachedReleases[includePrereleases] = release;
    _lastFetches[includePrereleases] = now;
    return release;
  }

  /// Picks the highest-versioned published release from a GitHub release list.
  ///
  /// The list endpoint is ordered by GitHub creation time, which can differ
  /// from version order when an older release is edited or republished.
  static AppRelease? latestEligibleRelease(Iterable<AppRelease> releases) {
    AppRelease? selected;
    AppVersion? selectedVersion;
    for (final release in releases) {
      if (release.draft) continue;
      final version = AppVersion.tryParse(release.versionLabel);
      if (version == null) continue;
      if (selectedVersion == null || version.compareTo(selectedVersion) > 0) {
        selected = release;
        selectedVersion = version;
      }
    }
    return selected;
  }

  /// Checks the latest release against the provided [currentVersion] and
  /// reports whether a newer build exists.
  static Future<UpdateSummary> checkForUpdates({
    required String currentVersion,
    bool forceRefresh = false,
    bool includePrereleases = false,
  }) async {
    final release = await fetchLatestRelease(
      forceRefresh: forceRefresh,
      includePrereleases: includePrereleases,
    );
    final releaseVersion = AppVersion.tryParse(release.versionLabel);
    final clientVersion = AppVersion.tryParse(currentVersion);
    final bool updateAvailable;
    if (releaseVersion == null || clientVersion == null) {
      updateAvailable = false;
    } else {
      updateAvailable = _isReleaseNewer(releaseVersion, clientVersion);
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

  /// Compares version labels using the same rules as a live update check.
  /// Exposed so platform-version edge cases can be covered without network
  /// requests.
  static bool isReleaseNewer({
    required String releaseVersion,
    required String currentVersion,
  }) {
    final release = AppVersion.tryParse(releaseVersion);
    final current = AppVersion.tryParse(currentVersion);
    if (release == null || current == null) return false;
    return _isReleaseNewer(release, current);
  }

  static bool _isReleaseNewer(AppVersion release, AppVersion current) {
    final normalizedCurrent = current.normalizedApplePrereleaseFor(release);
    return release.compareTo(normalizedCurrent) > 0;
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
  final List<String> prerelease;

  const AppVersion._(this.segments, this.prerelease);

  factory AppVersion(List<int> segments, {List<String> prerelease = const []}) {
    if (segments.isEmpty) {
      throw ArgumentError('segments cannot be empty');
    }
    return AppVersion._(
      List<int>.from(segments, growable: false),
      List<String>.from(prerelease, growable: false),
    );
  }

  static AppVersion? tryParse(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final match = RegExp(
      r'^v?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final parts = match
        .group(1)!
        .split('.')
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    if (parts.isEmpty) return null;
    final prerelease = match.group(2)?.split('.') ?? const <String>[];
    return AppVersion(parts, prerelease: prerelease);
  }

  /// Flutter flattens an Apple prerelease such as `0.9.4-alpha.1` to
  /// `0.9.4.1`. AppVersionInfo normally restores the original label from the
  /// bundled pubspec. This fallback keeps same-channel increment checks
  /// working if that metadata is unavailable in an older build.
  AppVersion normalizedApplePrereleaseFor(AppVersion release) {
    if (prerelease.isNotEmpty || release.prerelease.isEmpty) return this;
    if (segments.length != release.segments.length + 1) return this;
    for (var i = 0; i < release.segments.length; i++) {
      if (segments[i] != release.segments[i]) return this;
    }

    var numericIndex = -1;
    for (var i = release.prerelease.length - 1; i >= 0; i--) {
      if (int.tryParse(release.prerelease[i]) != null) {
        numericIndex = i;
        break;
      }
    }
    if (numericIndex < 0) return this;

    final normalizedPrerelease = List<String>.from(release.prerelease);
    normalizedPrerelease[numericIndex] = segments.last.toString();
    return AppVersion(release.segments, prerelease: normalizedPrerelease);
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

    if (prerelease.isEmpty && other.prerelease.isEmpty) return 0;
    if (prerelease.isEmpty) return 1;
    if (other.prerelease.isEmpty) return -1;

    final prereleaseLength = prerelease.length > other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var i = 0; i < prereleaseLength; i++) {
      if (i >= prerelease.length) return -1;
      if (i >= other.prerelease.length) return 1;
      final a = prerelease[i];
      final b = other.prerelease[i];
      if (a == b) continue;
      final aNumber = int.tryParse(a);
      final bNumber = int.tryParse(b);
      if (aNumber != null && bNumber != null) {
        return aNumber.compareTo(bNumber);
      }
      if (aNumber != null) return -1;
      if (bNumber != null) return 1;
      return a.compareTo(b);
    }
    return 0;
  }

  @override
  String toString() {
    final base = segments.join('.');
    return prerelease.isEmpty ? base : '$base-${prerelease.join('.')}';
  }
}

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => 'UpdateException: $message';
}
