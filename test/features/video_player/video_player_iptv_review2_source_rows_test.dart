import 'dart:async';
import 'dart:collection';
import 'package:debrify/models/torrent.dart';
import 'support/iptv_workflow_driver.dart';

/// Delegates the actual service result. A synchronous non-advancing conversion
/// must fail a finite read assertion, rather than starve Flutter's timeout.
class CandidateReads extends ListBase<StremioIptvCandidate> {
  CandidateReads(this.values);
  final List<StremioIptvCandidate> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only service result');
  @override
  StremioIptvCandidate operator [](int index) {
    expect(
      ++reads,
      lessThanOrEqualTo(64),
      reason:
          'A finite candidate list must not produce an unbounded row sequence',
    );
    return values[index];
  }

  @override
  void operator []=(int index, StremioIptvCandidate value) =>
      throw UnsupportedError('Read-only service result');
}

void main() {
  for (final matched in [false, true]) {
    testWidgets(
      'P15 review2 source browser receives finite direct rows and launch highlight matched=$matched',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        const urls = [
          'https://probe.test/first.ts',
          'https://probe.test/second.ts',
          'https://probe.test/third.ts',
        ];
        final live = await d.installAddon(
          'source-row-contract-$matched',
          urls: urls,
        );
        final deliveries = <CandidateReads>[];
        final reads = ZoneSpecification(
          registerUnaryCallback:
              <R, T>(self, parent, zone, R Function(T) callback) {
                final frame = StackTrace.current
                    .toString()
                    .split('\n')
                    .where((line) => line.contains('package:debrify/'))
                    .firstOrNull;
                final selected =
                    frame?.contains('initIptvStremioSources') ?? false;
                return parent.registerUnaryCallback(zone, (T value) {
                  if (selected && value is List<StremioIptvCandidate>) {
                    final observed = CandidateReads(value);
                    deliveries.add(observed);
                    return callback(observed as T);
                  }
                  return callback(value);
                });
              },
        );
        try {
          await runZoned(
            () => d.mount(
              [live],
              initialUrl: matched ? urls.last : 'https://probe.test/retired.ts',
            ),
            zoneSpecification: reads,
          );
          expect(deliveries, hasLength(1));
          expect(playerControls(t).onShowStremioSources, isNotNull);
          expect(d.errors, isEmpty);
          final sheet = await d.sources();
          expect(sheet.currentSourceIndex, matched ? 2 : 0);
          expect(sheet.sources, hasLength(3));
          for (var i = 0; i < sheet.sources.length; i++) {
            final row = sheet.sources[i];
            final url = urls[i];
            expect(row.rowid, i);
            expect(row.name, 'Candidate $i');
            expect(row.directUrl, url);
            expect(row.source, 'stremio');
            expect(row.streamType, StreamType.directUrl);
            expect(row.hasRealInfoHash, false);
            expect([
              row.sizeBytes,
              row.createdUnix,
              row.seeders,
              row.leechers,
              row.completed,
              row.scrapedDate,
            ], everyElement(0));
            // This is the public synthetic identity format, also used by direct
            // stream search results; it must remain stable for each URL.
            expect(
              row.infohash,
              'url:${url.hashCode.toRadixString(16).padLeft(40, '0')}',
            );
            expect(await d.f.finish(t, sheet.resolveSource(row)), url);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
