import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/iptv_storage_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  for (final caller in ['switch', 'replay']) {
    for (final boundary in ['tracking-read', 'admitted', 'transaction']) {
      for (final handoff in ['B', 'ABA', 'delete']) {
        for (final disposed in [false, true]) {
          testWidgets(
            'P15 $caller history $boundary handoff=$handoff disposed=$disposed pins physical rows',
            (t) async {
              final d = IptvWorkflowDriver(t);
              await d.initialize();
              final live = iptvChannel(
                0,
                url:
                    'https://p15-$caller-$handoff-$disposed.test/live/u/p/123.ts',
              );
              d.response = iptvPanelReply;
              final held = boundary == 'tracking-read'
                  ? IptvAwaitDelivery('recordIptvWatch', (v) => v is bool)
                  : boundary == 'admitted'
                  ? IptvAwaitDelivery('runScoped', (v) => v == null, skip: 1)
                  : IptvAwaitDelivery('recordWatch', (v) => v is int);
              try {
                await d.mount([live, iptvEpisode(1)]);
                final a = ProfileRuntime.capture();
                final s = await d.guide();
                final pending = d.observe(
                  () => held.run(
                    () => caller == 'replay'
                        ? s.onPlayProgramme!(live, iptvProgramme())
                        : s.onChannelSelected([live, iptvEpisode(1)], 1),
                  ),
                );
                await d.f.until(t, () => held.pending.isNotEmpty);
                if (disposed) {
                  await d.retire();
                }
                final transfer = await iptvHandoff(d, a, handoff);
                final incoming = transfer.current;
                held.release();
                await d.f.finish(t, pending);
                await d.settle();
                // A successful replay invokes the switch owner, which writes its history
                // a second time. That second write captures the incoming profile.
                if (boundary == 'tracking-read' ||
                    handoff == 'ABA' ||
                    caller == 'replay' && !disposed) {
                  Map<String, Map<String, dynamic>> current = {};
                  for (var attempt = 0; attempt < 50; attempt++) {
                    current = await d.f.finish(
                      t,
                      IptvHistoryStorage.getIptvWatchHistory(),
                    );
                    if (current.isNotEmpty) break;
                    await d.advance(const Duration(milliseconds: 20));
                  }
                  expect(current, isNotEmpty);
                }
                final rowsA = await t.runAsync(() => iptvPhysicalHistory(d, a));
                final rowsB = await t.runAsync(
                  () => iptvPhysicalHistory(d, incoming),
                );
                if (handoff == 'ABA') {
                  final rowsIntermediate = await t.runAsync(
                    () => iptvPhysicalHistory(d, transfer.intermediate),
                  );
                  expect(rowsIntermediate, isEmpty);
                }
                expect(
                  rowsA!.length,
                  boundary != 'tracking-read' || handoff == 'ABA' ? 1 : 0,
                );
                expect(
                  rowsB!.length,
                  boundary == 'tracking-read' ||
                          handoff == 'ABA' ||
                          caller == 'replay' && !disposed
                      ? 1
                      : 0,
                );
                final written = boundary == 'tracking-read' ? rowsB : rowsA;
                if (caller == 'switch') {
                  expect(written.single['series_id'], 'series');
                  expect(written.single['episode'], 1);
                } else {
                  expect(written.single['url'], contains('/timeshift/'));
                }
                expect(d.errors, isEmpty);
              } finally {
                held.release();
                await d.close();
              }
            },
          );
        }
      }
    }
  }
}
