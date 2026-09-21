import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 21);
  test('missing catalogs are due unless automatic updates are off', () {
    expect(IptvCatalogRefreshService.isDue(null, 24, now), isTrue);
    expect(IptvCatalogRefreshService.isDue(null, 0, now), isFalse);
  });
  test('each configured interval respects its boundary', () {
    for (final hours in [6, 12, 24, 48]) {
      final boundary = now
          .subtract(Duration(hours: hours))
          .millisecondsSinceEpoch;
      expect(
        IptvCatalogRefreshService.isDue(boundary + 1, hours, now),
        isFalse,
      );
      expect(IptvCatalogRefreshService.isDue(boundary, hours, now), isTrue);
      expect(IptvCatalogRefreshService.isDue(boundary - 1, hours, now), isTrue);
    }
  });
  test('future timestamps do not cause a refresh loop', () {
    expect(
      IptvCatalogRefreshService.isDue(
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        6,
        now,
      ),
      isFalse,
    );
  });
}
