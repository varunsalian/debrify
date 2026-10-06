import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/stremio_tv_catalogs_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CatalogFixture f;
  final net = CatalogNetwork();
  setUpAll(net.install);
  tearDownAll(() => net.client.close());
  setUp(() async {
    f = CatalogFixture();
    await f.open();
  });
  tearDown(() => f.close());
  test(
    'export first id and type match defaults movie, trims name, two-space JSON',
    () async {
      final first = catalog(type: null, name: '  First  ');
      await f.seed([catalog(type: 'series'), first, catalog(name: 'Second')]);
      final exported = await LocalCatalogExporter.loadCatalog(
        catalogId: 'cat',
        catalogType: 'movie',
      );
      expect(exported!.name, 'First');
      expect(exported.json, const JsonEncoder.withIndent('  ').convert(first));
      expect(jsonDecode(exported.json), first);
      expect(
        await LocalCatalogExporter.loadCatalog(
          catalogId: 'missing',
          catalogType: 'movie',
        ),
        isNull,
      );
    },
  );
  test('export empty trimmed name falls back to local_catalog', () async {
    await f.seed([catalog(name: '   ')]);
    expect(
      (await LocalCatalogExporter.loadCatalog(
        catalogId: 'cat',
        catalogType: 'movie',
      ))!.name,
      'local_catalog',
    );
  });
}
