import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/webdav_item.dart';
import '../utils/file_utils.dart';
import 'storage_service.dart';

class WebDavService {
  WebDavService._();

  static Future<WebDavConfig?> getConfig() async {
    return StorageService.getSelectedWebDavServer();
  }

  static Future<List<WebDavConfig>> getConfigs() {
    return StorageService.getWebDavServers();
  }

  static Future<bool> testConnection(WebDavConfig config) async {
    final items = await listDirectory(config: config, path: '');
    return items.isNotEmpty || config.baseUrl.isNotEmpty;
  }

  static Future<List<WebDavItem>> listDirectory({
    required WebDavConfig config,
    required String path,
  }) async {
    final uri = _uriForPath(config, path, collection: true);
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll(_headers(config))
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body =
          '''<?xml version="1.0" encoding="utf-8" ?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:getcontentlength/><D:getlastmodified/><D:getcontenttype/><D:resourcetype/></D:prop></D:propfind>''';

    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 20)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_formatWebDavError(response));
    }

    final document = XmlDocument.parse(response.body);
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
  }) async {
    final response = await http
        .delete(
          _uriForPath(config, item.path, collection: item.isDirectory),
          headers: _headers(config),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_formatWebDavError(response));
    }
  }

  static String directUrl(WebDavConfig config, String path) {
    return _uriForPath(config, path).toString();
  }

  static Map<String, String> authHeaders(WebDavConfig config) {
    return _headers(config);
  }

  static Uri _baseUri(WebDavConfig config) {
    final parsed = Uri.parse(config.baseUrl.trim());
    if (!parsed.hasScheme) {
      return Uri.parse('https://${config.baseUrl.trim()}');
    }
    return parsed;
  }

  static Uri _uriForPath(
    WebDavConfig config,
    String path, {
    bool collection = false,
  }) {
    final base = _baseUri(config);
    final baseSegments = base.pathSegments.where((s) => s.isNotEmpty).toList();
    final extraSegments = _normalizeDirPath(
      path,
    ).split('/').where((s) => s.isNotEmpty).toList();
    return base.replace(
      pathSegments: [...baseSegments, ...extraSegments, if (collection) ''],
    );
  }

  static Map<String, String> _headers(WebDavConfig config) {
    final headers = <String, String>{'Accept': '*/*'};
    if (config.username.isNotEmpty || config.password.isNotEmpty) {
      final token = base64Encode(
        utf8.encode('${config.username}:${config.password}'),
      );
      headers['Authorization'] = 'Basic $token';
    }
    return headers;
  }

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

  static String _formatWebDavError(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'WebDAV authentication failed';
    }
    if (response.statusCode == 404) return 'WebDAV folder not found';
    return 'WebDAV request failed: ${response.statusCode}';
  }
}
