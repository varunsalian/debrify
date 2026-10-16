import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 candidate ladder narrates each attempted row in order',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('candidate-narration');
      final previous = debugPrint;
      final messages = <String>[];
      try {
        await d.mount([iptvChannel(0), live]);
        debugPrint = (message, {wrapWidth}) {
          if (message != null) messages.add(message);
        };
        d.probeMode();
        final guide = await d.guide();
        final tune = d.observe(
          () => guide.onChannelSelected([iptvChannel(0), live], 1),
        );
        await d.f.until(t, () => d.opened.length == 2);
        await d.probeEvent('error');
        await d.f.until(t, () => d.opened.length == 3);
        await d.probeEvent('width');
        await d.f.finish(t, tune);
        final notes = messages
            .where((v) => v.contains('stremio candidate'))
            .toList();
        expect(notes, hasLength(2));
        expect(notes.first, endsWith('stremio candidate 1/2'));
        expect(notes.last, endsWith('stremio candidate 2/2'));
        expect(d.playingUrl, 'https://probe.test/second.ts');
        expect(d.errors, isEmpty);
      } finally {
        debugPrint = previous;
        await d.close();
      }
    },
  );
}
