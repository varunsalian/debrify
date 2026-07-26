import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/xmltv_epg_source.dart';

void main() {
  // All times sit around this instant so the parser's ±window keeps them.
  final now = DateTime.utc(2026, 7, 26, 12, 0, 0);
  final nowMs = now.millisecondsSinceEpoch;

  const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="test">
  <channel id="ESPN.us"><display-name>ESPN</display-name></channel>
  <programme start="20260726100000 +0000" stop="20260726130000 +0000" channel="ESPN.us">
    <title lang="en">NBA Finals</title>
    <title lang="es">Finales de la NBA</title>
    <desc><![CDATA[Game 4 & the "decider".]]></desc>
  </programme>
  <programme start="20260726150000 +0200" stop="20260726170000 +0200" channel="ESPN.us">
    <title>SportsCenter</title>
  </programme>
  <programme start="20260726120000 +0000" stop="20260726140000 +0000" channel="Ignored.uk">
    <title>Should be filtered out</title>
  </programme>
  <programme start="20260720000000 +0000" stop="20260720010000 +0000" channel="ESPN.us">
    <title>Way outside the window</title>
  </programme>
  <programme start="20260726180000 +0000" stop="20260726190000 +0000" channel="ESPN.us">
    <icon src="x"/>
    <title>Evening Show</title>
  </programme>
</tv>
''';

  Future<Map<String, List<List<Object?>>>> parse(List<int> bytes) async {
    final dir = await Directory.systemTemp.createTemp('xmltv_test');
    final file = File('${dir.path}/guide.xml');
    await file.writeAsBytes(bytes);
    try {
      return await XmltvEpgSource.parseXmltvFile(
        file.path,
        {'ESPN.us'},
        nowMs,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  test('parses, filters and windows a plain XMLTV file', () async {
    final index = await parse(xml.codeUnits);
    expect(index.keys, ['ESPN.us']);
    final rows = index['ESPN.us']!;
    // Out-of-window and other-channel programmes dropped.
    expect(rows.length, 3);
    // Sorted by start; first title wins over the second language.
    expect(rows[0][2], 'NBA Finals');
    expect(rows[0][3], 'Game 4 & the "decider".');
    expect(rows[0][0], DateTime.utc(2026, 7, 26, 10).millisecondsSinceEpoch);
    // +0200 offset converted: 15:00+0200 == 13:00 UTC.
    expect(rows[1][2], 'SportsCenter');
    expect(rows[1][0], DateTime.utc(2026, 7, 26, 13).millisecondsSinceEpoch);
    expect(rows[1][3], '');
    // Self-closing <icon/> before the title didn't derail the state machine.
    expect(rows[2][2], 'Evening Show');
  });

  test('parses the same file gzipped (magic-byte detection)', () async {
    final index = await parse(gzip.encode(xml.codeUnits));
    expect(index['ESPN.us']!.length, 3);
    expect(index['ESPN.us']![0][2], 'NBA Finals');
  });

  test('returns empty for a file with no matching channels', () async {
    final index = await parse('<tv></tv>'.codeUnits);
    expect(index, isEmpty);
  });

  test('synthesizes missing stop from the next programme start', () async {
    const noStops = '''
<tv>
  <programme start="20260726110000 +0000" channel="ESPN.us">
    <title>First</title>
  </programme>
  <programme start="20260726123000 +0000" channel="ESPN.us">
    <title>Second</title>
  </programme>
</tv>
''';
    final index = await parse(noStops.codeUnits);
    final rows = index['ESPN.us']!;
    expect(rows.length, 2);
    // First runs until Second starts.
    expect(rows[0][1], DateTime.utc(2026, 7, 26, 12, 30).millisecondsSinceEpoch);
    // Last entry falls back to start + 3h.
    expect(rows[1][1], DateTime.utc(2026, 7, 26, 15, 30).millisecondsSinceEpoch);
  });
}
