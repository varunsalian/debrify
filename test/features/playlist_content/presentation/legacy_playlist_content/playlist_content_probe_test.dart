import 'package:flutter_test/flutter_test.dart';
import '../../../../support/playlist_content_fixture.dart';

void main() {
  testWidgets(
    'original HTTP fixture real RD tree non-monotonic ids',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      expect(f.root.getAllFiles().map((n) => n.fileId), [9, 2, 5]);
      f.member('navigateIntoFolder')(f.visible.single);
      expect(f.visible.map((n) => n.name), [
        '10. Ten.mkv',
        '2. Two.mkv',
        'readme.txt',
      ]);
      expect(f.log, ['GET api.real-debrid.com/rest/1.0/torrents/info/rd9']);
    }),
  );
  testWidgets(
    'original launcher rejection probe callback notify stop snackbar',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t, started: () => f.events.add('callback'));
      final probe = PlaylistContentProbe(f)..install();
      try {
        await f.invoke(t, () => f.member('playFile')(f.root.getAllFiles()[1]));
        await t.pump(const Duration(milliseconds: 600));
        expect(f.events, ['callback', 'launch 1', 'launch 2', 'stopped']);
        expect(probe.calls, 2);
        expect(probe.stops, 1);
        expect(
          find.text('Player settings could not be loaded. Please try again.'),
          findsOneWidget,
        );
        expect(f.log, [
          'GET api.real-debrid.com/rest/1.0/torrents/info/rd9',
          'GET api.real-debrid.com/rest/1.0/torrents/info/rd9',
          'POST api.real-debrid.com/rest/1.0/unrestrict/link',
        ]);
        expect(f.requests.last.body, 'link=https%3A%2F%2Flocked.test%2F2');
      } finally {
        probe.remove();
      }
    }),
  );
}
