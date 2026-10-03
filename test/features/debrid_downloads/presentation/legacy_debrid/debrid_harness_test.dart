import 'package:flutter_test/flutter_test.dart';
import '../../../../support/debrid_downloads_fixture.dart';

void main() {
  testWidgets(
    'original runtime and vault harness reaches both real HTTP libraries',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      expect(f.member('apiKey'), 'fixture-key');
      expect((f.member('torrents') as List).map((dynamic row) => row.id), [
        'z9',
        'a2',
        'm5',
      ]);
      expect((f.member('downloads') as List).map((dynamic row) => row.id), [
        'w8',
        'b3',
        'n6',
      ]);
      expect(f.requests.map((r) => r.url.path), [
        '/rest/1.0/torrents',
        '/rest/1.0/downloads',
      ]);
      expect(
        f.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer fixture-key',
        ),
        isTrue,
      );
    }),
  );
}
