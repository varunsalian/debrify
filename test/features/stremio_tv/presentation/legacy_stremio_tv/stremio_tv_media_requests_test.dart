import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_fixture.dart';

// Committed-profile transport uses an isolated test-suite process.
void main() {
  testWidgets('C3 (O) both URL-only searches issue no media-server requests', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await t.runAsync(f.installMediaServer);
      await f.mount(t);
      await f.play(t);
      final player = f.observer.players.single;
      expect(
        f.requests.any((r) => r.url.host == 'media-original.test'),
        isFalse,
      );
      f.requests.clear();
      expect(
        await t.runAsync(() => player.stremioTvNextProvider!(f.channelId(1))),
        isNotNull,
      );
      expect(
        f.requests.any((r) => r.url.host == 'media-original.test'),
        isFalse,
      );
      expect(f.requests.any((r) => r.url.path.contains('/stream/')), isTrue);
    });
  });
}
