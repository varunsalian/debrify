import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 closing a retired guide cancels a request begun by a rejected replay callback without reading context',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      try {
        await d.mount([live]);
        final sheet = await d.guide();
        await d.retire();
        Object? replayError;
        await d.f.finish(
          t,
          d.observe(() async {
            try {
              await sheet.onPlayProgramme!(live, iptvProgramme(airing: false));
            } catch (error) {
              replayError = error;
            }
          }),
        );
        expect(replayError, isA<FlutterError>());
        expect(replayError.toString(), contains('has been unmounted'));
        Object? closeError;
        try {
          sheet.onClose();
        } catch (error) {
          closeError = error;
        }
        // Dispose cancelled the original gate. The rejected replay began a new
        // one before its existing context rejection, so this cancel is active.
        expect(closeError, isA<FlutterError>());
        expect(
          closeError.toString(),
          contains('setState() called after dispose'),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
