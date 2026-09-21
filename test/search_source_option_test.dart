import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/search_source_dropdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('addon search source shows the user alias', () {
    final addon = StremioAddon(
      id: 'com.test.aio',
      name: 'AIOStreams',
      userAlias: 'AIOStreams Backup',
      manifestUrl: 'https://example.com/backup/manifest.json',
      baseUrl: 'https://example.com/backup',
    );

    expect(
      SearchSourceOption.fromAddon(addon).label,
      'AIOStreams Backup',
    );
  });
}
