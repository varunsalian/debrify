import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/xmltv_epg_source.dart';

/// The JSON `epg_cache` shipped in v0.6.3-alpha.1, so real installs upgrade
/// through the one-time import into the catalog database. These cases cover
/// what happens when that import FAILS — the state transition, not just the
/// retention decision.
///
/// The failure is induced honestly: the guide is imported through a database
/// path that cannot be opened, so `ingestEpgGuide` throws exactly as it would
/// on a full or locked disk.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getTemporaryPath() async {
    final dir = Directory('$root/tmp');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory('$root/support');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }
}

void main() {
  late Directory storageRoot;
  late Directory dbDir;
  late HttpServer server;
  late String epgUrl;
  late File legacyFile;
  late String guideKey;

  // A guide whose channel does NOT match what the playlist asks for, so the
  // parse succeeds and matches nothing — the empty-parse branch.
  const nonMatchingXml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<tv><channel id="somebodyelse.tv">'
      '<display-name>Somebody Else</display-name></channel></tv>';

  setUp(() async {
    storageRoot = await Directory.systemTemp.createTemp('epg_retention');
    PathProviderPlatform.instance = _FakePathProvider(storageRoot.path);

    dbDir = await Directory.systemTemp.createTemp('epg_retention_db');
    IptvCatalogDb.debugDirectoryOverride = dbDir.path;
    await IptvCatalogDb.open();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType('application', 'xml');
      request.response.write(nonMatchingXml);
      request.response.close();
    });
    epgUrl = 'http://127.0.0.1:${server.port}/xmltv.php';
    guideKey = md5.convert(utf8.encode(epgUrl)).toString();

    // A legacy snapshot holding a guide worth keeping.
    final cacheDir = Directory('${storageRoot.path}/support/epg_cache');
    await cacheDir.create(recursive: true);
    legacyFile = File('${cacheDir.path}/$guideKey.json');
    await legacyFile.writeAsString(jsonEncode({
      'v': 2,
      'epgUrl': epgUrl,
      'fetchedAt': DateTime.now().toIso8601String(),
      'channels': {
        'wanted.id': [
          [
            DateTime.now().millisecondsSinceEpoch,
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
            'Cached Show',
            'From the legacy file',
          ],
        ],
      },
      'names': <String, String>{},
      'sawWanted': true,
    }));
  });

  tearDown(() async {
    await server.close(force: true);
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await storageRoot.delete(recursive: true);
    await dbDir.delete(recursive: true);
  });

  test('a failed import + empty parse leaves the guide retriable', () async {
    // An unopenable database path: the import throws, exactly as it would if
    // the device were out of space.
    final unusableDbPath = dbDir.path; // a directory, not a database file

    await XmltvEpgSource.load(
      epgUrl: epgUrl,
      tvgIds: {'wanted.id'},
      channelNames: const {},
      dbPath: unusableDbPath,
    );

    expect(
      await legacyFile.exists(),
      isTrue,
      reason: 'the file is the only copy of this guide until it imports',
    );
    expect(
      IptvCatalogDb.epgGuideInfo(guideKey),
      isNull,
      reason: 'writing the empty-guide marker here would satisfy info != null '
          'on the next load, skip the legacy import and strand the file '
          'forever',
    );
  });

  test('a guide with nothing to import is still dropped', () async {
    // An unreadable/rowless file has nothing to lose and nothing to retry —
    // keeping it would retry an import that can never succeed on every open.
    await legacyFile.writeAsString('not json at all');

    await XmltvEpgSource.load(
      epgUrl: epgUrl,
      tvgIds: {'wanted.id'},
      channelNames: const {},
      dbPath: dbDir.path,
    );

    expect(await legacyFile.exists(), isFalse);
  });
}
