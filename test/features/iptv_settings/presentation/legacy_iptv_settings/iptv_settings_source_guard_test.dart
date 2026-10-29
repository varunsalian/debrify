import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String compact(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=[)\]}])'), '');
void main() {
  test('IPTV settings never take the catalog DB exclusive lock', () {
    final allSources = [
      File('lib/screens/settings/iptv_settings_page.dart'),
      ...Directory('lib/features/iptv_settings')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];
    for (final body in allSources.map((f) => f.readAsStringSync())) {
      expect(body, isNot(contains('runExclusive')));
    }
  });
  test('a non-zero refresh interval immediately refreshes due catalogs', () {
    final service = File(
      'lib/services/iptv_catalog_refresh_service.dart',
    ).readAsStringSync();
    expect(
      compact(service),
      contains('if(hours!=0)unawaited(instance.refreshDue());'),
    );
  });
}
