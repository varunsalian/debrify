import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../models/webdav_item.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import '../utils/file_utils.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'storage_service.dart';
import 'webdav_protocol_client.dart';

class WebDavService {
  WebDavService._();

  static Future<WebDavConfig?> getConfig({
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    return StorageService.getSelectedWebDavServer(
      forSettings: false,
      feature: feature,
    );
  }

  static Future<List<WebDavConfig>> getConfigs({
    ProfileFeature feature = ProfileFeature.cloud,
  }) {
    return StorageService.getWebDavServers(
      forSettings: false,
      feature: feature,
    );
  }

  static Future<bool> testConnection(
    WebDavConfig config, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    await _authorize(config, feature: feature, allowUnbound: true);
    final items = await _listDirectoryRaw(config: config, path: '');
    return items.isNotEmpty || config.baseUrl.isNotEmpty;
  }

  static Future<List<WebDavItem>> listDirectory({
    required WebDavConfig config,
    required String path,
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    await _authorize(config, feature: feature);
    return _listDirectoryRaw(config: config, path: path);
  }

  static Future<List<WebDavItem>> _listDirectoryRaw({
    required WebDavConfig config,
    required String path,
  }) async {
    final client = _protocolClient(config);
    late final WebDavBytesResult response;
    try {
      response = await client.propfind(
        path: path,
        depth: 1,
        collection: true,
        body:
            '''<?xml version="1.0" encoding="utf-8" ?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:getcontentlength/><D:getlastmodified/><D:getcontenttype/><D:resourcetype/></D:prop></D:propfind>''',
      );
    } finally {
      client.close();
    }
    late final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(response.bytes));
    } on XmlException catch (error) {
      throw WebDavException.malformed(
        'WebDAV returned an invalid directory listing',
        cause: error,
      );
    } on FormatException catch (error) {
      throw WebDavException.malformed(
        'WebDAV returned a non-UTF-8 directory listing',
        cause: error,
      );
    }
    final basePath = _normalizeDirPath(_pathFromUri(_baseUri(config)));
    final currentPath = _normalizeDirPath(path);
    final results = <WebDavItem>[];

    for (final node in document.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'response') continue;
      final href = _childText(node, 'href');
      if (href == null || href.trim().isEmpty) continue;

      final itemPath = _relativePathFromHref(href, basePath);
      if (_samePath(itemPath, currentPath)) continue;

      final displayName = _childText(node, 'displayname');
      final isDirectory = node.descendants.whereType<XmlElement>().any(
        (element) => element.name.local == 'collection',
      );
      final name = _cleanName(displayName, itemPath, isDirectory);
      if (name.isEmpty) continue;

      final size = int.tryParse(_childText(node, 'getcontentlength') ?? '');
      final modified = _parseHttpDate(_childText(node, 'getlastmodified'));
      final contentType = _childText(node, 'getcontenttype');

      results.add(
        WebDavItem(
          name: name,
          path: _normalizePath(itemPath, directory: isDirectory),
          isDirectory: isDirectory,
          sizeBytes: size,
          modifiedAt: modified,
          contentType: contentType,
        ),
      );
    }

    results.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return results;
  }

  static Future<List<WebDavItem>> collectVideoFiles({
    required WebDavConfig config,
    required WebDavItem folder,
    int maxFiles = 1000,
  }) async {
    final collected = <WebDavItem>[];

    Future<void> walk(String path) async {
      if (collected.length >= maxFiles) return;
      final children = await listDirectory(config: config, path: path);
      for (final child in children) {
        if (collected.length >= maxFiles) return;
        if (child.isDirectory) {
          await walk(child.path);
        } else if (FileUtils.isVideoFile(child.name)) {
          collected.add(child);
        }
      }
    }

    await walk(folder.path);
    return collected;
  }

  static Future<List<WebDavItem>> collectFiles({
    required WebDavConfig config,
    required WebDavItem folder,
    int maxFiles = 1000,
  }) async {
    final collected = <WebDavItem>[];

    Future<void> walk(String path) async {
      if (collected.length >= maxFiles) return;
      final children = await listDirectory(config: config, path: path);
      for (final child in children) {
        if (collected.length >= maxFiles) return;
        if (child.isDirectory) {
          await walk(child.path);
        } else {
          collected.add(child);
        }
      }
    }

    await walk(folder.path);
    return collected;
  }

  static Future<void> delete({
    required WebDavConfig config,
    required WebDavItem item,
    ProfileFeature feature = ProfileFeature.cloud,
    Future<void> Function()? beforeSend,
  }) async {
    await _authorize(config, feature: feature);
    final client = _protocolClient(config);
    try {
      await client.deletePath(
        path: item.path,
        collection: item.isDirectory,
        beforeSend: beforeSend,
      );
    } finally {
      client.close();
    }
  }

  static Future<WebDavResponseMetadata> putBytes({
    required WebDavConfig config,
    required String path,
    required List<int> bytes,
    required int maxBytes,
    String contentType = 'application/octet-stream',
    String? ifNoneMatch,
    String? ifMatch,
    ProfileFeature feature = ProfileFeature.cloud,
    Future<void> Function()? beforeSend,
  }) async {
    await _authorize(config, feature: feature);
    final client = _protocolClient(config);
    try {
      return await client.putBytes(
        path: path,
        bytes: bytes,
        maxBytes: maxBytes,
        contentType: contentType,
        ifNoneMatch: ifNoneMatch,
        ifMatch: ifMatch,
        beforeSend: beforeSend,
      );
    } finally {
      client.close();
    }
  }

  static Future<WebDavResponseMetadata> uploadFile({
    required WebDavConfig config,
    required String path,
    required File file,
    required int maxBytes,
    String contentType = 'application/octet-stream',
    String? ifNoneMatch,
    String? ifMatch,
    ProfileFeature feature = ProfileFeature.cloud,
    Future<void> Function()? beforeSend,
  }) async {
    await _authorize(config, feature: feature);
    final client = _protocolClient(config);
    try {
      return await client.uploadFile(
        path: path,
        file: file,
        maxBytes: maxBytes,
        contentType: contentType,
        ifNoneMatch: ifNoneMatch,
        ifMatch: ifMatch,
        beforeSend: beforeSend,
      );
    } finally {
      client.close();
    }
  }

  static Future<WebDavBytesResult> getBytes({
    required WebDavConfig config,
    required String path,
    required int maxBytes,
    ProfileFeature feature = ProfileFeature.cloud,
    Future<void> Function()? beforeSend,
  }) async {
    await _authorize(config, feature: feature);
    final client = _protocolClient(config);
    try {
      return await client.getBytes(
        path: path,
        maxBytes: maxBytes,
        beforeSend: beforeSend,
      );
    } finally {
      client.close();
    }
  }

  static Future<WebDavFileResult> downloadToFile({
    required WebDavConfig config,
    required String path,
    required File destination,
    required int maxBytes,
    ProfileFeature feature = ProfileFeature.cloud,
    Future<void> Function()? beforeSend,
  }) async {
    await _authorize(config, feature: feature);
    final client = _protocolClient(config);
    try {
      return await client.downloadToFile(
        path: path,
        destination: destination,
        maxBytes: maxBytes,
        beforeSend: beforeSend,
      );
    } finally {
      client.close();
    }
  }

  static Future<bool> exists({
    required WebDavConfig config,
    required String path,
    bool collection = false,
    ProfileFeature feature = ProfileFeature.cloud,
    Future<void> Function()? beforeSend,
  }) async {
    await _authorize(config, feature: feature);
    final client = _protocolClient(config);
    try {
      return (await client.exists(
        path: path,
        collection: collection,
        beforeSend: beforeSend,
      )).exists;
    } finally {
      client.close();
    }
  }

  static String directUrl(WebDavConfig config, String path) =>
      WebDavProtocolClient.resolvePath(
        endpoint: _baseUri(config),
        path: path,
      ).toString();

  static Map<String, String> authHeaders(WebDavConfig config) =>
      WebDavProtocolClient.buildAuthorizationHeaders(_credentials(config));

  static bool isInsecureConfig(WebDavConfig config) =>
      WebDavProtocolClient.isInsecureUrl(config.baseUrl);

  static bool isInsecureUrl(String url) =>
      WebDavProtocolClient.isInsecureUrl(url);

  static Future<void> _authorize(
    WebDavConfig config, {
    ProfileFeature feature = ProfileFeature.cloud,
    bool allowUnbound = false,
  }) => ProfileCollectionResourceFacade.authorizeExecution(
    resourceId: config.connectionResourceId,
    resourceRevision: config.connectionResourceRevision,
    acceptedTypes: const <ConnectionResourceType>{
      ConnectionResourceType.webDav,
    },
    feature: feature,
    allowUnbound: allowUnbound,
  );

  static Uri _baseUri(WebDavConfig config) {
    return WebDavProtocolClient.parseEndpoint(config.baseUrl);
  }

  static WebDavProtocolClient _protocolClient(WebDavConfig config) =>
      WebDavProtocolClient(
        endpoint: _baseUri(config),
        credentials: _credentials(config),
        timeout: const Duration(seconds: 20),
      );

  static WebDavCredentials _credentials(WebDavConfig config) =>
      WebDavCredentials(username: config.username, password: config.password);

  static String? _childText(XmlElement element, String localName) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (child.name.local == localName) return child.innerText.trim();
    }
    return null;
  }

  static String _pathFromUri(Uri uri) {
    return Uri.decodeFull(uri.path);
  }

  static String _relativePathFromHref(String href, String basePath) {
    Uri? hrefUri = Uri.tryParse(href);
    String path = hrefUri?.path ?? href;
    path = _normalizeDirPath(Uri.decodeFull(path));
    if (basePath.isNotEmpty && path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    }
    return _normalizeDirPath(path);
  }

  static String _normalizeDirPath(String path) {
    var value = path.trim();
    if (value.startsWith('/')) value = value.substring(1);
    while (value.contains('//')) {
      value = value.replaceAll('//', '/');
    }
    return value;
  }

  static String _normalizePath(String path, {required bool directory}) {
    var value = _normalizeDirPath(path);
    if (directory && value.isNotEmpty && !value.endsWith('/')) {
      value = '$value/';
    }
    return value;
  }

  static bool _samePath(String a, String b) {
    return _normalizeDirPath(a).replaceAll(RegExp(r'/+$'), '') ==
        _normalizeDirPath(b).replaceAll(RegExp(r'/+$'), '');
  }

  static String _cleanName(String? displayName, String path, bool isDirectory) {
    final fromDisplay = displayName?.trim();
    if (fromDisplay != null && fromDisplay.isNotEmpty) return fromDisplay;
    final normalized = _normalizePath(
      path,
      directory: isDirectory,
    ).replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return '';
    return normalized.split('/').last;
  }

  static DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return HttpDate.parse(value);
  }
}
