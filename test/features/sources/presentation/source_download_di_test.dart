import 'package:debrify/features/sources/application/source_playback_dependencies.dart';
import 'package:debrify/features/sources/data/source_download.dart';
import 'package:debrify/features/sources/presentation/source_playback_bridge.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Downloads extends SourceDownload {
  final requests = <Torrent>[];
  @override
  Future<SourceDownloadStatus> download(
    Torrent source, {
    required bool Function() canContinue,
    void Function(SourceDownloadStatus)? onProgress,
  }) async {
    expect(canContinue(), isTrue);
    requests.add(source);
    onProgress?.call(SourceDownloadStatus.resolving);
    return SourceDownloadStatus.queued;
  }
}

void main() {
  testWidgets(
    'real playback bridge uses injected download operation and feedback',
    (tester) async {
      final downloads = Downloads();
      final source = Torrent(
        rowid: 1,
        infohash: 'url:fixture',
        name: 'Fixture',
        sizeBytes: 0,
        createdUnix: 0,
        seeders: 0,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        streamType: StreamType.directUrl,
        directUrl: 'https://fixture.test/video',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sourceDownloadProvider.overrideWithValue(downloads)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => ref
                      .read(sourcePlaybackBridgeProvider)
                      .download(context, source),
                  child: const Text('Download'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(downloads.requests, [source]);
      expect(find.text('Resolving download URL…'), findsOneWidget);
      // Feedback retains the original three-second snackbar lifetime.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Download queued.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
