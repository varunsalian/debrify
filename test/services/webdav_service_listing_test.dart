// Folder listings: large documents are parsed off the UI isolate with the same
// result as small ones, and a broken large document fails as a WebDAV error.
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_service.dart';
import 'package:flutter_test/flutter_test.dart';

String listing(int folders) {
  final out = StringBuffer(
    '<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">'
    '<D:response><D:href>/dav/</D:href><D:propstat><D:prop>'
    '<D:resourcetype><D:collection/></D:resourcetype></D:prop>'
    '</D:propstat></D:response>',
  );
  for (var i = folders - 1; i >= 0; i--) {
    final name = 'Show.Name.$i.S01.1080p.WEB-DL.DDP5.1.H.264-GROUP';
    out.write(
      '<D:response><D:href>/dav/${Uri.encodeComponent(name)}/</D:href>'
      '<D:propstat><D:prop><D:displayname>$name</D:displayname>'
      '<D:getlastmodified>Tue, 18 Nov 2026 10:00:00 GMT</D:getlastmodified>'
      '<D:resourcetype><D:collection/></D:resourcetype></D:prop>'
      '<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>',
    );
  }
  out.write(
    '<D:response><D:href>/dav/readme.mkv</D:href><D:propstat><D:prop>'
    '<D:displayname>readme.mkv</D:displayname>'
    '<D:getcontentlength>123</D:getcontentlength>'
    '<D:resourcetype/></D:prop></D:propstat></D:response>',
  );
  out.write('</D:multistatus>');
  return out.toString();
}

void main() {
  late HttpServer server;
  late String body;
  late WebDavConfig config;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 207
        ..headers.contentType = ContentType(
          'application',
          'xml',
          charset: 'utf-8',
        )
        ..add(utf8.encode(body));
      await request.response.close();
    });
    config = WebDavConfig(
      id: 'local',
      name: 'Local',
      baseUrl: 'http://127.0.0.1:${server.port}/dav/',
      username: '',
      password: '',
    );
  });

  tearDown(() => server.close(force: true));

  Future<List<WebDavItem>> list({int? maxBytes}) => WebDavService.listDirectory(
    config: config,
    path: '',
    maxBytes: maxBytes ?? WebDavProtocolClient.defaultSmallDocumentLimit,
  );

  test('a large listing parses in the background like a small one', () async {
    body = listing(3);
    final small = await list();
    expect(small.map((item) => item.isDirectory), [true, true, true, false]);
    expect(small.first.name, 'Show.Name.0.S01.1080p.WEB-DL.DDP5.1.H.264-GROUP');
    expect(small.last.sizeBytes, 123);

    body = listing(4000);
    expect(
      utf8.encode(body).length,
      greaterThan(WebDavService.backgroundParseBytes),
    );
    final large = await list(maxBytes: 12 * 1024 * 1024);
    expect(large, hasLength(4001));
    expect(large.first.name, 'Show.Name.0.S01.1080p.WEB-DL.DDP5.1.H.264-GROUP');
    expect(large.first.path, endsWith('/'));
    expect(large.first.modifiedAt, DateTime.utc(2026, 11, 18, 10));
    expect(large.last.name, 'readme.mkv');
  });

  test('a broken large listing is a WebDAV error, not a crash', () async {
    body = '${listing(4000)}<D:unclosed';
    await expectLater(
      list(maxBytes: 12 * 1024 * 1024),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.kind,
          'kind',
          WebDavErrorKind.malformedResponse,
        ),
      ),
    );
  });

  test('a listing over its size limit is refused', () async {
    body = listing(4000);
    await expectLater(
      list(maxBytes: 64 * 1024),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.message,
          'message',
          contains('byte limit'),
        ),
      ),
    );
  });

  test('names and folders that servers report unevenly', () async {
    String response(String href, {String? name, bool collection = false}) =>
        '<D:response><D:href>$href</D:href><D:propstat><D:prop>'
        '${name == null ? '' : '<D:displayname>$name</D:displayname>'}'
        '<D:resourcetype>${collection ? '<D:collection/>' : ''}'
        '</D:resourcetype></D:prop></D:propstat></D:response>';
    body =
        '<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">'
        '${response('/dav/', collection: true)}'
        // The display name drops the extension.
        '${response('/dav/Dune%20(2021).mkv', name: 'Dune (2021)')}'
        // The display name is still percent-encoded.
        '${response('/dav/Heat%20(1995).mkv', name: 'Heat%20(1995).mkv')}'
        // A folder without <collection/>; its address ends in "/".
        '${response('/dav/Movies/', name: 'Movies')}'
        // A folder's display name needs no extension.
        '${response('/dav/Shows/', name: 'TV', collection: true)}'
        // A real "%20" in a name stays.
        '${response('/dav/Rate%20100%2520Pct.mkv', name: 'Rate 100%20Pct.mkv')}'
        '</D:multistatus>';
    final items = {for (final item in await list()) item.name: item};
    expect(
      items.keys,
      unorderedEquals([
        'Dune (2021).mkv',
        'Heat (1995).mkv',
        'Rate 100%20Pct.mkv',
        'Movies',
        'TV',
      ]),
    );
    expect(items['Movies']!.isDirectory, isTrue);
    expect(items['Movies']!.path, 'Movies/');
    expect(items['Dune (2021).mkv']!.isDirectory, isFalse);
  });
}
