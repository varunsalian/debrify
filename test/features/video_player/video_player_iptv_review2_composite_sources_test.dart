import 'package:debrify/models/torrent.dart';
import 'support/iptv_workflow_driver.dart';

Torrent compositeRow(int index) => Torrent(
  rowid: index,
  infohash: 'url:000000000000000000000000000000000000000$index',
  name: 'Composite source $index',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'stremio',
  streamType: StreamType.directUrl,
  directUrl: 'https://p15-composite.test/$index.mp4',
  hasRealInfoHash: false,
);

void main() {
  for (final rowsOnly in [false, true]) {
    testWidgets(
      'P15 review2 an IPTV clear retires a partial TV source override rowsOnly=$rowsOnly',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(0);
        final rows = [compositeRow(0), compositeRow(1)];
        Future<String?> resolve(Torrent row) async => row.directUrl;
        try {
          await d.observe(
            () => d.f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: live.url,
                title: live.name,
                iptvChannels: [live],
                iptvStartIndex: 0,
                stremioSources: rowsOnly ? null : rows,
                resolveStremioSource: rowsOnly ? resolve : null,
                stremioTvCurrentChannelId: 'old-tv',
                stremioTvNextProvider: (_) async => <String, dynamic>{
                  'url': rows.first.directUrl,
                  'title': 'Next TV',
                  'channelId': 'new-tv',
                  if (rowsOnly)
                    'stremioSources': rows.map((v) => v.toJson()).toList(),
                  if (!rowsOnly) 'sourceResolver': resolve,
                },
              ),
            ),
          );
          expect(playerControls(t).onShowStremioSources, isNull);
          expect(playerControls(t).onNext, isNotNull);
          d.observe(playerControls(t).onNext!);
          await d.f.until(t, () => d.opened.length == 2);
          await d.settle();
          expect(playerControls(t).onShowStremioSources, isNotNull);
          await d.pick([iptvChannel(9)], 0);
          expect(playerControls(t).onShowStremioSources, isNull);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 an empty initial IPTV resolve preserves the fallback movie source protocol',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('composite-empty', urls: []);
      final rows = [compositeRow(0), compositeRow(1)];
      try {
        await d.observe(
          () => d.f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: rows.first.directUrl!,
              title: live.name,
              iptvChannels: [live],
              iptvStartIndex: 0,
              stremioSources: rows,
              stremioCurrentSourceIndex: 0,
              resolveStremioSource: (row) async => row.directUrl,
            ),
          ),
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path.contains('/stream/tv/'),
          ),
        );
        await d.settle();
        d.player.state = d.player.state.copyWith(
          position: const Duration(seconds: 42),
        );
        d.player.emit('position', const Duration(seconds: 42));
        await d.settle();
        final sources = await d.sources();
        d.observe(() => sources.onSourceSelected(1, rows[1].directUrl!));
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        await d.probeEvent('width');
        await d.probeEvent('position');
        await d.advance(const Duration(seconds: 3));
        await d.settle();
        expect(
          d.calls('seek').map((v) => v.$2),
          contains(const Duration(seconds: 42)),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.probeEvent('width');
        await d.close();
      }
    },
  );
}
