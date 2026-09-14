import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:synchronized/synchronized.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../utils/app_storage.dart';
import '../diagnostic_log.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_feature.dart';

final class WebDavLogTarget {
  const WebDavLogTarget({
    required this.key,
    required this.deviceId,
    required this.location,
    required this.credentials,
    required this.revision,
  });
  final String key;
  final String deviceId;
  final WebDavSyncFolderLocation location;
  final WebDavCredentials credentials;
  final String revision;
  String get folder =>
      location.folderPath.isEmpty ? 'logs' : '${location.folderPath}/logs';
  String get file => '$folder/device-$deviceId.jsonl';
}

enum WebDavLogUploadResult { uploaded, unavailable, busy, failed }

/// Optional device-owned diagnostics. Never enters a profile or sync payload.
class WebDavLogUpload with WidgetsBindingObserver {
  WebDavLogUpload({
    required this.target,
    required this.readOptIn,
    required this.writeOptIn,
    required this.export,
    WebDavProtocolClient Function(WebDavLogTarget)? clientFactory,
    this.deadline = const Duration(seconds: 45),
  }) : clientFactory =
           clientFactory ??
           ((t) => WebDavProtocolClient(
             endpoint: t.location.endpoint,
             credentials: t.credentials,
             timeout: const Duration(seconds: 20),
           ));

  static final instance = WebDavLogUpload(
    target: _activeTarget,
    readOptIn: () async {
      final file = await _configFile();
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      return value is Map && value['enabledTarget'] is String
          ? value['enabledTarget'] as String
          : null;
    },
    writeOptIn: (key) async {
      final file = await _configFile();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode({'enabledTarget': key}), flush: true);
      await temp.rename(file.path);
    },
    export: () => DiagnosticLog.instance.exportLastWindow(
      maxBytes: maxUploadBytes - 1024,
    ),
  );
  static Future<File> _configFile() async =>
      File('${(await AppStorage.support()).path}/webdav-log-upload.json');

  static Future<WebDavLogTarget?> _activeTarget() async {
    if (!WebDavSyncFeature.enabled || !DiagnosticLog.instance.isAvailable) {
      return null;
    }
    final store = WebDavSyncBindingStore();
    final snapshot = await store.load();
    final binding = snapshot.activeBinding;
    if (binding == null ||
        binding.lifecycle != WebDavSyncLifecycle.active ||
        WebDavSyncBindingStore.logoutPending(snapshot)) {
      return null;
    }
    final ns = snapshot.namespaceFor(binding);
    if (ns == null) return null;
    final secrets = await store.readSecrets(binding);
    return WebDavLogTarget(
      key: '${binding.id}:${ns.deviceId}',
      deviceId: ns.deviceId,
      location: binding.location,
      revision: binding.sealedSecrets,
      credentials: WebDavCredentials(
        username: secrets.username,
        password: secrets.password,
      ),
    );
  }

  final Future<WebDavLogTarget?> Function() target;
  final Future<String?> Function() readOptIn;
  final Future<void> Function(String?) writeOptIn;
  final Future<DiagnosticLogExport> Function() export;
  final WebDavProtocolClient Function(WebDavLogTarget) clientFactory;
  final Duration deadline;
  final _settingsLock = Lock();
  static const maxUploadBytes = 2 * 1024 * 1024;
  Timer? _timer;
  bool _foreground = true;
  bool _busy = false;
  int _generation = 0;
  WebDavProtocolClient? _client;
  DateTime? lastUploaded;

  Future<bool> isEnabled() async {
    final current = await target();
    return current != null && await readOptIn() == current.key;
  }

  Future<void> setEnabled(bool enabled) => _settingsLock.synchronized(() async {
    _generation++;
    _client?.close();
    final current = await target();
    if (enabled && current == null) throw StateError('Connect WebDAV first');
    await writeOptIn(enabled ? current!.key : null);
    if (enabled) unawaited(upload());
  });

  void start() {
    if (_timer != null) return;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    // Give startup and the initial sync priority over optional diagnostics.
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_foreground) unawaited(upload());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _generation++;
      _client?.close();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _client?.close();
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<WebDavLogUploadResult> upload() async {
    if (_busy) return WebDavLogUploadResult.busy;
    if (!_foreground) return WebDavLogUploadResult.unavailable;
    _busy = true;
    final generation = ++_generation;
    try {
      return await _upload(generation).timeout(deadline);
    } catch (_) {
      // No sync receipts, global loaders, recursive log errors or user alerts.
      return WebDavLogUploadResult.failed;
    } finally {
      _generation++;
      _client?.close();
      _client = null;
      _busy = false;
    }
  }

  Future<WebDavLogUploadResult> _upload(int generation) async {
    final current = await target();
    if (current == null || await readOptIn() != current.key) {
      return WebDavLogUploadResult.unavailable;
    }
    Future<void> guard() async {
      if (!_foreground || generation != _generation) {
        throw StateError('Canceled');
      }
      final latest = await target();
      if (generation != _generation ||
          latest?.key != current.key ||
          latest?.revision != current.revision ||
          await readOptIn() != current.key) {
        throw StateError('Connection changed');
      }
      if (generation != _generation) throw StateError('Canceled');
    }

    final snapshot = await export();
    String? version;
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 2),
      );
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    await guard();
    final client = clientFactory(current);
    _client = client;
    await client.ensureCollection(current.folder, beforeSend: guard);
    await client.putBytes(
      path: current.file,
      bytes: snapshotBytes(snapshot, current.deviceId, appVersion: version),
      maxBytes: maxUploadBytes,
      contentType: 'application/x-ndjson',
      beforeSend: guard,
    );
    await guard();
    lastUploaded = DateTime.now();
    return WebDavLogUploadResult.uploaded;
  }

  /// Complete JSONL records only; retain the newest tail within a fixed budget.
  static Uint8List snapshotBytes(
    DiagnosticLogExport snapshot,
    String deviceId, {
    String? appVersion,
  }) {
    final header = utf8.encode(
      '${jsonEncode({'event': 'webdav_log_snapshot', 'deviceId': deviceId, 'platform': Platform.operatingSystem, if (appVersion != null) 'appVersion': appVersion, 'windowEnd': snapshot.windowEnd.toUtc().toIso8601String(), 'truncated': snapshot.truncated || snapshot.bytes.length > maxUploadBytes - 1024})}\n',
    );
    final budget = maxUploadBytes - 1024;
    var start = snapshot.bytes.length > budget
        ? snapshot.bytes.length - budget
        : 0;
    if (start > 0) {
      while (start < snapshot.bytes.length && snapshot.bytes[start - 1] != 10) {
        start++;
      }
    }
    return Uint8List.fromList([...header, ...snapshot.bytes.sublist(start)]);
  }
}
