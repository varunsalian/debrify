import 'package:debrify/services/series_source_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SeriesSource cloudSource({
  required String provider,
  required String id,
  String kind = SeriesSource.cloudKindFolder,
}) {
  return SeriesSource(
    torrentHash: '',
    torrentName: '$provider $id',
    debridService: provider,
    debridTorrentId: id,
    cloudSourceKind: kind,
    boundAt: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('provider-native source survives JSON round trip', () {
    final source = cloudSource(provider: 'premiumize', id: 'folder-1');
    final restored = SeriesSource.fromJson(source.toJson());

    expect(restored.cloudSourceKind, SeriesSource.cloudKindFolder);
    expect(restored.isProviderNativeCloud, isTrue);
    expect(restored.bindingKey, 'cloud:premiumize:folder:folder-1');
  });

  test('provider web download is a native cloud source', () {
    final source = cloudSource(
      provider: 'torbox',
      id: '42',
      kind: SeriesSource.cloudKindWebDownload,
    );
    final restored = SeriesSource.fromJson(source.toJson());

    expect(restored.isProviderNativeCloud, isTrue);
    expect(restored.cloudSourceKind, SeriesSource.cloudKindWebDownload);
    expect(restored.bindingKey, 'cloud:torbox:web_download:42');
  });

  test('opaque cloud reference does not persist a saved-link URL', () {
    const link = 'https://host.test/private-token/video.mkv';
    final reference = SeriesSource.opaqueCloudReference(link);

    expect(reference, hasLength(64));
    expect(reference, isNot(contains('private-token')));
    expect(reference, SeriesSource.opaqueCloudReference(link));
  });

  test('hash-backed binding identity remains hash based', () {
    final source = SeriesSource(
      torrentHash: 'ABC123',
      torrentName: 'Pack',
      debridService: 'rd',
      debridTorrentId: 'torrent-1',
      boundAt: 1,
    );

    expect(source.isProviderNativeCloud, isFalse);
    expect(source.bindingKey, 'hash:ABC123');
  });

  test('different hashless cloud sources coexist and dedupe exactly', () async {
    final premiumize = cloudSource(provider: 'premiumize', id: 'folder-1');
    final pikpak = cloudSource(provider: 'pikpak', id: 'folder-1');
    final premiumizeReplacement = SeriesSource(
      torrentHash: '',
      torrentName: 'Updated folder name',
      debridService: 'premiumize',
      debridTorrentId: 'folder-1',
      cloudSourceKind: SeriesSource.cloudKindFolder,
      boundAt: 2,
    );

    await SeriesSourceService.addSource('tt001', premiumize);
    await SeriesSourceService.addSource('tt001', pikpak);
    await SeriesSourceService.addSource('tt001', premiumizeReplacement);

    final stored = await SeriesSourceService.getSources('tt001');
    expect(stored, hasLength(2));
    expect(
      stored.firstWhere((s) => s.debridService == 'premiumize').torrentName,
      'Updated folder name',
    );
    expect(stored.any((s) => s.debridService == 'pikpak'), isTrue);
  });

  test('removes only the requested hashless cloud source', () async {
    final first = cloudSource(provider: 'premiumize', id: 'folder-1');
    final second = cloudSource(provider: 'premiumize', id: 'folder-2');
    await SeriesSourceService.addSource('tt001', first);
    await SeriesSourceService.addSource('tt001', second);

    await SeriesSourceService.removeSourceEntry('tt001', first);

    final stored = await SeriesSourceService.getSources('tt001');
    expect(stored, hasLength(1));
    expect(stored.single.debridTorrentId, 'folder-2');
  });
}
