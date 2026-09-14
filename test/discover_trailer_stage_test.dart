import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/see_all/discover_trailer_stage.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:debrify/models/stremio_addon.dart';

void main() {
  testWidgets('card-change clears trailer safely during sibling rebuild', (
    tester,
  ) async {
    final streams = ValueNotifier<YoutubeResolvedStreams?>(
      const YoutubeResolvedStreams(playUrl: 'https://example.invalid/a.mp4'),
    );
    final loading = ValueNotifier(false);
    final volume = ValueNotifier(0.0);
    final meta = ValueNotifier<StremioMeta?>(null);
    Widget page(bool clear) => MaterialApp(
      home: Stack(
        children: [
          DiscoverTrailerStage(
            trailer: streams,
            loading: loading,
            volume: volume,
            meta: meta,
            railRect: const Rect.fromLTWH(0, 0, 300, 200),
          ),
          Builder(
            builder: (_) {
              if (clear) streams.value = null;
              return const SizedBox();
            },
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(false));
    await tester.pumpWidget(page(true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(DiscoverTrailerStage), findsOneWidget);
    expect(find.byType(HeroTrailerBackdrop), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
