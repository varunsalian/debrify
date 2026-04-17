import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpHeaders, Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AptabaseService {
  static const String _appKey = 'A-EU-3659871446';
  static const String _sdkVersion = 'debrify_aptabase@1';
  static final http.Client _httpClient = http.Client();
  static final String _sessionId = _newSessionId();

  static bool _initialized = false;
  static Uri? _apiUrl;
  static String _appVersion = 'unknown';
  static String _buildNumber = 'unknown';

  static Future<void> init() async {
    if (_initialized) return;

    final apiUrl = _resolveApiUrl(_appKey);
    if (apiUrl == null) {
      debugPrint('AptabaseService: invalid app key, analytics disabled');
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
    } catch (error, stackTrace) {
      debugPrint('AptabaseService: package info failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    _apiUrl = apiUrl;
    _initialized = true;
  }

  static Future<void> track(
    String eventName, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) async {
    if (!_initialized || _apiUrl == null) return;

    final normalizedProps = <String, dynamic>{};
    for (final entry in properties.entries) {
      final value = _normalizeValue(entry.value);
      if (value != null) {
        normalizedProps[entry.key] = value;
      }
    }

    final body = <Map<String, dynamic>>[
      <String, dynamic>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'sessionId': _sessionId,
        'eventName': eventName,
        'systemProps': <String, dynamic>{
          'isDebug': kDebugMode,
          'osName': currentPlatformLabel(),
          'osVersion': _osVersion(),
          'locale': _localeName(),
          'appVersion': _appVersion,
          'appBuildNumber': _buildNumber,
          'sdkVersion': _sdkVersion,
        },
        'props': normalizedProps,
      },
    ];

    try {
      final response = await _httpClient
          .post(
            _apiUrl!,
            headers: <String, String>{
              'App-Key': _appKey,
              HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
              if (!kIsWeb) HttpHeaders.userAgentHeader: _sdkVersion,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      final responseBody = response.body;

      if (response.statusCode >= 200 && response.statusCode < 300) return;

      debugPrint(
        'AptabaseService: send failed for "$eventName" '
        'status=${response.statusCode} body=$responseBody',
      );
    } catch (error, stackTrace) {
      debugPrint('AptabaseService: send exception for "$eventName": $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static void trackInBackground(
    String eventName, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    unawaited(track(eventName, properties));
  }

  static String currentPlatformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static Uri? _resolveApiUrl(String appKey) {
    final parts = appKey.split('-');
    if (parts.length != 3) return null;

    switch (parts[1]) {
      case 'EU':
        return Uri.parse('https://eu.aptabase.com/api/v0/events');
      case 'US':
        return Uri.parse('https://us.aptabase.com/api/v0/events');
      default:
        return null;
    }
  }

  static String _osVersion() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystemVersion;
  }

  static String _localeName() {
    if (kIsWeb) return 'web';
    return Platform.localeName;
  }

  static String _newSessionId() {
    final random = Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List<String>.generate(
      24,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  static Object? _normalizeValue(Object? value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    return value.toString();
  }
}
