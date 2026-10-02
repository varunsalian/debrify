import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show Platform;
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/storage/device_storage.dart';
import 'package:debrify/services/update_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsUpdates {
  SettingsUpdates(this._summaries, this._deps);
  final ({
    Future<bool> Function(ProfileFeature feature) ensureProfileFeature,
    Future<void> Function(UpdateSummary summary) showReleaseDetails,
    void Function(String message) showSnack,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;
  final SettingsSummaries _summaries;
  void dispose() {
    _updateDownloadSub?.cancel();
  }

  StreamSubscription<Map<String, dynamic>>? _updateDownloadSub;

  String? _updateDownloadTaskId;

  Future<void> checkForAppUpdates() async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.appUpdates)) return;
    if (!_deps.mounted()) return;
    if (_summaries.checkingUpdates) return;
    if (_summaries.currentVersionName.isEmpty) return;
    await DeviceStorage.setIgnoredUpdateVersion(null);

    _deps.setState(() {
      _summaries.checkingUpdates = true;
      _summaries.updateSubtitle = 'Checking GitHub releases...';
    });

    try {
      final summary = await UpdateService.checkForUpdates(
        currentVersion: _summaries.currentVersionName,
        includePrereleases: _summaries.includeAlphaUpdates,
      );
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _summaries.updateSubtitle = summary.updateAvailable
            ? 'Update available (${summary.release.versionLabel})'
            : 'You are on the latest build';
        _summaries.checkingUpdates = false;
      });
      await _deps.showReleaseDetails(summary);
    } on UpdateException catch (err) {
      _deps.showSnack(err.message);
      if (_deps.mounted()) {
        _deps.setState(() {
          _summaries.updateSubtitle = 'Unable to reach GitHub releases';
          _summaries.checkingUpdates = false;
        });
      }
    } catch (_) {
      _deps.showSnack('Could not check for updates. Please try again later.');
      if (_deps.mounted()) {
        _deps.setState(() {
          _summaries.updateSubtitle = 'Unable to reach GitHub releases';
          _summaries.checkingUpdates = false;
        });
      }
    }
  }

  Future<void> toggleAutoUpdateChecks(bool enabled) async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.appUpdates)) return;
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _summaries.autoUpdateChecksEnabled = enabled;
    });
    await DeviceStorage.setUpdateAutoCheckEnabled(enabled);
  }

  Future<void> toggleIncludeAlphaUpdates(bool enabled) async {
    if (!await _deps.ensureProfileFeature(ProfileFeature.appUpdates)) return;
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _summaries.includeAlphaUpdates = enabled;
      _summaries.updateSubtitle = enabled
          ? 'Check for alpha and beta builds'
          : 'Check for beta updates';
    });
    await DeviceStorage.setUpdateIncludeAlphaEnabled(enabled);
  }

  Future<void> startAndroidUpdateDownload(AppRelease release) async {
    if (kIsWeb) {
      await openReleasesPage(release.htmlUrl);
      return;
    }
    if (!Platform.isAndroid) {
      await openReleasesPage(release.htmlUrl);
      return;
    }
    if (_updateDownloadTaskId != null) {
      _deps.showSnack('An update download is already running.');
      return;
    }
    final asset = release.androidApkAsset;
    if (asset == null) {
      _deps.showSnack('No Android APK is attached to this release yet.');
      await openReleasesPage(release.htmlUrl);
      return;
    }
    final hasPermission = await ensureInstallPermission();
    if (!hasPermission) return;

    if (_deps.mounted()) {
      _deps.setState(() {
        _summaries.updateSubtitle = 'Downloading ${release.versionLabel}...';
      });
    }

    String? taskId;
    const mime = 'application/vnd.android.package-archive';
    try {
      taskId = await AndroidNativeDownloader.startUpdate(
        url: asset.downloadUrl.toString(),
        fileName: asset.name.isNotEmpty
            ? asset.name
            : 'Debrify-${release.versionLabel}.apk',
        subDir: 'Debrify/Updates',
        mimeType: mime,
      );
    } catch (_) {
      taskId = null;
    }

    if (taskId == null) {
      _deps.showSnack(
        'Could not start the update download. Please try again later.',
      );
      if (_deps.mounted()) {
        _deps.setState(() {
          _summaries.updateSubtitle = 'Download failed to start';
        });
      }
      return;
    }

    _updateDownloadTaskId = taskId;
    _updateDownloadSub?.cancel();
    _updateDownloadSub = AndroidNativeDownloader.events.listen((event) async {
      final String eventTaskId = (event['taskId'] ?? '').toString();
      if (eventTaskId != _updateDownloadTaskId) return;
      final type = event['type']?.toString();
      if (type == 'complete') {
        final contentUri = (event['contentUri'] ?? '').toString();
        final eventMime = (event['mimeType'] ?? '').toString().isNotEmpty
            ? (event['mimeType'] ?? '').toString()
            : mime;
        try {
          _deps.showSnack('Update downloaded. Opening installer...');
          if (contentUri.isNotEmpty) {
            final ok = await AndroidNativeDownloader.openContentUri(
              contentUri,
              eventMime,
            );
            if (!ok) {
              _deps.showSnack('Installer was opened from Downloads instead.');
            }
          }
        } catch (_) {
          _deps.showSnack(
            'Could not launch the installer. Check your Downloads app.',
          );
        } finally {
          clearUpdateDownloadListener();
          if (_deps.mounted()) {
            _deps.setState(() {
              _summaries.updateSubtitle =
                  'Installer ready for ${release.versionLabel}';
            });
          }
        }
      } else if (type == 'error' || type == 'canceled') {
        _deps.showSnack('Update download did not finish. Please try again.');
        clearUpdateDownloadListener();
        if (_deps.mounted()) {
          _deps.setState(() {
            _summaries.updateSubtitle = 'Download failed';
          });
        }
      }
    });

    _deps.showSnack(
      'Downloading the update in the background. Check notifications for progress.',
    );
  }

  Future<bool> ensureInstallPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final currentStatus = await Permission.requestInstallPackages.status;
    if (currentStatus.isGranted) return true;
    final result = await Permission.requestInstallPackages.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied || result.isRestricted) {
      _deps.showSnack('Allow Debrify to install apps from your settings.');
      unawaited(openAppSettings());
    } else {
      _deps.showSnack('Permission required to install the downloaded update.');
    }
    return false;
  }

  Future<void> openReleasesPage(Uri url) async {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      _deps.showSnack('Unable to open the releases page right now.');
    }
  }

  void clearUpdateDownloadListener() {
    _updateDownloadSub?.cancel();
    _updateDownloadSub = null;
    _updateDownloadTaskId = null;
  }
}
