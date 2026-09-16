import 'package:debrify/services/android_local_source_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('debrify/local_sources');
  const tree = 'content://storage/tree/primary%3AShows';
  final calls = <MethodCall>[];
  var inaccessible = false;
  var rows = <Map<String, Object>>[];
  Map<String, Object> document(
    String id,
    String name, {
    bool folder = false,
    int size = 1000,
  }) => {
    'uri': id,
    'name': name.split('/').last,
    'relativePath': name,
    'isDirectory': folder,
    'sizeBytes': size,
    'modifiedAt': 12,
  };
  setUp(() {
    calls.clear();
    inaccessible = false;
    rows = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (inaccessible) throw PlatformException(code: 'permission_denied');
          if (call.method == 'pickDirectory') {
            return document(tree, 'Show', folder: true);
          }
          if (call.method == 'pickFile') return null;
          if (call.method == 'listFiles') return rows;
          if (call.method == 'stat') {
            return document(call.arguments['uri'] as String, 'Movie.mkv');
          }
          throw UnsupportedError(call.method);
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('picker cancellation creates no source', () async {
    expect(await AndroidLocalSourceService.pick(directory: false), isNull);
  });

  test(
    'saved folder round-trips its opaque URI and resolves exact episode',
    () async {
      final selected = await AndroidLocalSourceService.pick(directory: true);
      final source = SeriesSource.fromJson(selected!.toSource().toJson());
      expect(source.localPath, isNull);
      expect(source.localUri, tree);
      expect(source.isLocalSeriesFolder, isTrue);
      rows = [
        document('$tree/document/opaque%2Ftwo', 'Season 2/Show.S02E01.mkv'),
        document('$tree/document/opaque%2Fone', 'Season 1/Show.S01E01.mkv'),
        document('$tree/document/readme', 'readme.txt'),
      ];
      final result = await AndroidLocalSourceService.resolve(
        source,
        season: 2,
        episode: 1,
      );
      expect(result.startIndex, 1);
      expect(result.playlist.length, 2);
      expect(result.playlist[1].url, '$tree/document/opaque%2Ftwo');
      expect(result.playlist[1].relativePath, 'Season 2/Show.S02E01.mkv');
      expect(calls.last.arguments, {'uri': tree});
    },
  );

  test(
    'sample files are excluded and largest duplicate episode is chosen',
    () async {
      rows = [
        document('$tree/document/small', 'Show.S01E01.720p.mkv', size: 100),
        document('$tree/document/large', 'Show.S01E01.1080p.mkv', size: 200),
        document('$tree/document/sample', 'Show.S01E02.sample.mkv', size: 300),
      ];
      final episodes = AndroidLocalSourceService.episodes(
        await AndroidLocalSourceService.videos(tree),
      );
      expect(episodes.length, 1);
      expect(episodes.single.document.uri, '$tree/document/large');
    },
  );

  test('revoked access fails, then the same saved source recovers', () async {
    final source = LocalSourceDocument.fromMap(
      document(tree, 'Show', folder: true),
    ).toSource();
    final saved = source.toJson();
    inaccessible = true;
    await expectLater(
      AndroidLocalSourceService.resolve(source, season: 1, episode: 1),
      throwsA(isA<PlatformException>()),
    );
    expect(source.toJson(), saved);
    inaccessible = false;
    rows = [document('$tree/document/1', 'Show.S01E01.mp4')];
    expect(
      (await AndroidLocalSourceService.resolve(
        source,
        season: 1,
        episode: 1,
      )).playlist.single.url,
      '$tree/document/1',
    );
  });

  test('missing episode fails rather than playing another episode', () async {
    final source = LocalSourceDocument.fromMap(
      document(tree, 'Show', folder: true),
    ).toSource();
    rows = [document('$tree/document/1', 'Show.S01E01.mp4')];
    await expectLater(
      AndroidLocalSourceService.resolve(source, season: 1, episode: 9),
      throwsA(isA<LocalSourceUnavailable>()),
    );
  });

  test(
    'movie selected within a tree retains its grant-bearing document URI',
    () async {
      const uri = '$tree/document/primary%3AShows%2FMovie.mkv';
      final source = LocalSourceDocument.fromMap(
        document(uri, 'Movie.mkv'),
      ).toSource();
      final reloaded = SeriesSource.fromJson(source.toJson());
      expect(reloaded.isLocalMovieFile, isTrue);
      final result = await AndroidLocalSourceService.resolve(reloaded);
      expect(result.playlist.single.url, uri);
      expect(calls.single.method, 'stat');
      expect(calls.single.arguments, {'uri': uri});
    },
  );
}
