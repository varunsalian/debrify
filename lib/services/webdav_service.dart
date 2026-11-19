import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:debrify/services/storage/webdav_server_storage.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../models/webdav_item.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import '../utils/file_utils.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'webdav_protocol_client.dart';

class WebDavService {
  WebDavService._();

  static Future<WebDavConfig?> getConfig({
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    return WebdavServerStorage.getSelectedWebDavServer(
      forSettings: false,
      feature: feature,
    );
  }

  static Future<List<WebDavConfig>> getConfigs({
    ProfileFeature feature = ProfileFeature.cloud,
  }) {
    return WebdavServerStorage.getWebDavServers(
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

  /// [maxBytes] bounds the listing document; very large folders (a debrid
  /// server's flat torrent list) may need more than the default.
  static Future<List<WebDavItem>> listDirectory({
    required WebDavConfig config,
    required String path,
    ProfileFeature feature = ProfileFeature.cloud,
    int maxBytes = WebDavProtocolClient.defaultSmallDocumentLimit,
  }) async {
    await _authorize(config, feature: feature);
    return _listDirectoryRaw(config: config, path: path, maxBytes: maxBytes);
  }

  /// Rechecks that the active profile may still use [config], without any
  /// network request. Throws when access was revoked or the server changed.
  static Future<void> authorizeUse(
    WebDavConfig config, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) => _authorize(config, feature: feature);

  /// Listings above this size are parsed on a background isolate so a huge
  /// folder cannot stall the UI thread.
  static const backgroundParseBytes = 64 * 1024;

  static Future<List<WebDavItem>> _listDirectoryRaw({
    required WebDavConfig config,
    required String path,
    int maxBytes = WebDavProtocolClient.defaultSmallDocumentLimit,
  }) async {
    final client = _protocolClient(config);
    late final WebDavBytesResult response;
    try {
      response = await client.propfind(
        path: path,
        depth: 1,
        collection: true,
        maxBytes: maxBytes,
        body:
            '''<?xml version="1.0" encoding="utf-8" ?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:getcontentlength/><D:getlastmodified/><D:getcontenttype/><D:resourcetype/></D:prop></D:propfind>''',
      );
    } finally {
      client.close();
    }
    final basePath = _normalizeDirPath(_pathFromUri(_baseUri(config)));
    final currentPath = _normalizeDirPath(path);
    final bytes = response.bytes;
    if (bytes.length < backgroundParseBytes) {
      return _parseListing(bytes, basePath, currentPath);
    }
    return Isolate.run(() {
      try {
        return _parseListing(bytes, basePath, currentPath);
      } on WebDavException catch (error) {
        // The parser's cause is not needed across the isolate boundary.
        throw WebDavException.malformed(error.message);
      }
    });
  }

  static const _listingFields = {
    'href',
    'displayname',
    'getcontentlength',
    'getlastmodified',
    'getcontenttype',
  };

  /// Reads the multistatus document as a stream of events rather than a
  /// whole tree, so a folder with thousands of entries stays light on memory.
  /// Each `response` keeps the first value of each property, as before.
  static List<WebDavItem> _parseListing(
    Uint8List bytes,
    String basePath,
    String currentPath,
  ) {
    late final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException catch (error) {
      throw WebDavException.malformed(
        'WebDAV returned a non-UTF-8 directory listing',
        cause: error,
      );
    }
    final results = <WebDavItem>[];
    var responseDepth = 0;
    var depth = 0;
    final fields = <String, String>{};
    var isDirectory = false;
    String? field;
    var fieldDepth = 0;
    final value = StringBuffer();

    void addResponse() {
      final href = fields['href'];
      if (href == null || href.trim().isEmpty) return;
      final itemPath = _relativePathFromHref(href, basePath);
      if (_samePath(itemPath, currentPath)) return;
      final name = _cleanName(fields['displayname'], itemPath, isDirectory);
      if (name.isEmpty) return;
      results.add(
        WebDavItem(
          name: name,
          path: _normalizePath(itemPath, directory: isDirectory),
          isDirectory: isDirectory,
          sizeBytes: int.tryParse(fields['getcontentlength'] ?? ''),
          modifiedAt: _parseHttpDate(fields['getlastmodified']),
          contentType: fields['getcontenttype'],
        ),
      );
    }

    try {
      for (final event in parseEvents(
        text,
        validateNesting: true,
        validateDocument: true,
      )) {
        if (event is XmlStartElementEvent) {
          final local = event.localName;
          if (!event.isSelfClosing) depth++;
          if (responseDepth == 0) {
            if (local == 'response' && !event.isSelfClosing) {
              responseDepth = depth;
              fields.clear();
              isDirectory = false;
            }
            continue;
          }
          if (local == 'collection') isDirectory = true;
          if (field == null &&
              _listingFields.contains(local) &&
              !fields.containsKey(local)) {
            if (event.isSelfClosing) {
              fields[local] = '';
            } else {
              field = local;
              fieldDepth = depth;
              value.clear();
            }
          }
        } else if (event is XmlEndElementEvent) {
          if (field != null && depth == fieldDepth) {
            fields[field] = value.toString().trim();
            field = null;
          }
          if (responseDepth != 0 && depth == responseDepth) {
            addResponse();
            responseDepth = 0;
          }
          depth--;
        } else if (field != null) {
          if (event is XmlTextEvent) value.write(event.value);
          if (event is XmlCDATAEvent) value.write(event.value);
        }
      }
    } on XmlException catch (error) {
      throw WebDavException.malformed(
        'WebDAV returned an invalid directory listing',
        cause: error,
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

  /// A date the server formats oddly is left out rather than failing the
  /// whole listing.
  static DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return HttpDate.parse(value);
    } on Object {
      return null;
    }
  }
}
