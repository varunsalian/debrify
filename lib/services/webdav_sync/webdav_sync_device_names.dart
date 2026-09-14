import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:synchronized/synchronized.dart';
import '../profiles/profile_preferences.dart';

import '../../utils/platform_util.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_transport.dart';

/// Optional, encrypted device metadata. Never added to the strict v1 manifest:
/// older clients can continue syncing without understanding device names.
abstract final class WebDavSyncDeviceNames {
  static const preferenceKey = 'webdav_sync_local_device_name_v1';
  static const maxLength = 60;
  static const maxBytes = 4096;
  // A timed-out caller may still have an HTTP PUT in flight. Keep subsequent
  // publications behind it so a manual rename is the last write, not the old
  // automatic name that happened to finish late.
  static final _publicationLock = Lock();

  static String validate(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.runes.length > maxLength ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const FormatException(
        'Enter a device name of 1–60 characters without line breaks.',
      );
    }
    return name;
  }

  static Future<String> localName() async {
    final prefs = await DevicePreferences.instance();
    final saved = prefs.getString(preferenceKey);
    if (saved != null) {
      try {
        return validate(saved);
      } on FormatException {
        /* Use the default. */
      }
    }
    String? name;
    try {
      name = await PlatformUtil.getDeviceName();
      if (name == null && Platform.isIOS && !PlatformUtil.isTvOS) {
        name = (await DeviceInfoPlugin().iosInfo).name;
      }
      if (name == null &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        name = Platform.localHostname;
      }
      if (name != null) return validate(name);
    } catch (_) {
      /* Platform names are best effort. */
    }
    return PlatformUtil.isTvOS
        ? 'Apple TV'
        : Platform.isAndroid
        ? 'Android device'
        : Platform.isIOS
        ? 'iPhone or iPad'
        : 'Debrify device';
  }

  static Future<void> saveLocal(String name) async {
    final prefs = await DevicePreferences.instance();
    if (!await prefs.setString(preferenceKey, validate(name))) {
      throw StateError('Could not save the device name');
    }
  }

  static Future<String?> read({
    required WebDavSyncTransport transport,
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
  }) async {
    if (transport is! WebDavSyncDeviceNameTransport) return null;
    try {
      final bytes = await (transport as WebDavSyncDeviceNameTransport)
          .readDeviceName(deviceId)
          .timeout(const Duration(seconds: 2));
      if (bytes == null) return null;
      final value = await codec.openDocument(
        key: root.key,
        encoded: bytes.bytes,
        circleId: root.document.circleId,
        deviceId: deviceId,
        logicalName: 'device-name',
        schemaVersion: 1,
        maxBytes: maxBytes,
      );
      if (value is! Map || value['name'] is! String) return null;
      return validate(value['name'] as String);
    } catch (_) {
      // Missing, damaged or unavailable optional metadata cannot hide a device
      // or prevent data synchronization and removal.
      return null;
    }
  }

  static Future<void> publish({
    required WebDavSyncTransport transport,
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    String? name,
    Future<void> Function()? beforeWrite,
  }) => _publicationLock.synchronized(
    () => _publish(
      transport: transport,
      codec: codec,
      root: root,
      deviceId: deviceId,
      name: name,
      beforeWrite: beforeWrite,
    ),
  );

  static Future<void> _publish({
    required WebDavSyncTransport transport,
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    String? name,
    Future<void> Function()? beforeWrite,
  }) async {
    if (transport is! WebDavSyncDeviceNameTransport) return;
    final value = validate(name ?? await localName());
    if (await read(
          transport: transport,
          codec: codec,
          root: root,
          deviceId: deviceId,
        ) ==
        value) {
      return;
    }
    final bytes = await codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'device-name',
      schemaVersion: 1,
      payload: {'name': value},
      maxBytes: maxBytes,
    );
    await beforeWrite?.call();
    await (transport as WebDavSyncDeviceNameTransport).writeDeviceName(
      deviceId,
      bytes,
    );
    if (await read(
          transport: transport,
          codec: codec,
          root: root,
          deviceId: deviceId,
        ) !=
        value) {
      throw StateError(
        'Could not verify the saved device name. Please try again.',
      );
    }
  }
}
