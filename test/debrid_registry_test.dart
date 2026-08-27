import 'package:debrify/features/debrid/descriptor.dart';
import 'package:debrify/app/wiring.dart';
import 'package:debrify/theme/debrid_brand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('provider ids', () {
    test('every spelling of Real-Debrid resolves to one provider', () {
      for (final spelling in [
        'debrid',
        'realdebrid',
        'real-debrid',
        'real_debrid',
        'rd',
        'RealDebrid',
        '  rd  ',
      ]) {
        expect(
          DebridProviderIds.normalize(spelling),
          DebridProviderIds.realDebrid,
          reason: spelling,
        );
      }
    });

    test('non-providers normalize to nothing', () {
      for (final other in [
        null,
        '',
        'none',
        'auto',
        'webdav',
        'local',
        'stream',
      ]) {
        expect(DebridProviderIds.normalize(other), isNull, reason: '$other');
      }
    });

    test('each descriptor answers to its own three id spaces', () {
      for (final provider in DebridProviders.all) {
        for (final id in [provider.id, provider.cloudKey, provider.sourceKey]) {
          expect(DebridProviders.find(id), same(provider), reason: id);
        }
        expect(provider.aliases, contains(provider.id));
        expect(provider.aliases, contains(provider.cloudKey));
        expect(provider.aliases, contains(provider.sourceKey));
      }
    });

    test('no two providers claim the same alias', () {
      final seen = <String, String>{};
      for (final provider in DebridProviders.all) {
        for (final alias in provider.aliases) {
          expect(
            seen.containsKey(alias),
            isFalse,
            reason: '$alias claimed by ${seen[alias]} and ${provider.id}',
          );
          seen[alias] = provider.id;
        }
      }
    });
  });

  group('registry', () {
    // The production graph, so this asserts what the app actually builds
    // rather than a table written twice.
    final registry = ServiceGraph.production().debrid;

    test('every descriptor has an implementation, in the same order', () {
      expect(
        registry.all.map((p) => p.descriptor).toList(),
        DebridProviders.all,
      );
    });

    test('lookups accept any spelling and refuse non-providers', () {
      expect(registry.find('rd')?.descriptor, DebridProviders.realDebrid);
      expect(registry.find('TORBOX')?.descriptor, DebridProviders.torbox);
      expect(registry.find('webdav'), isNull);
      expect(registry.find(null), isNull);
    });

    test('capabilities match what the flows branch on', () {
      expect(DebridProviders.torbox.capabilities.cacheCheck, isTrue);
      expect(DebridProviders.premiumize.capabilities.cacheCheck, isTrue);
      expect(DebridProviders.realDebrid.capabilities.cacheCheck, isFalse);
      expect(DebridProviders.pikpak.capabilities.addsQueueDownloads, isTrue);
      expect(
        DebridProviders.realDebrid.capabilities.skipsBlockedTorrents,
        isTrue,
      );
      // A non-provider source must read as capability-free rather than throw.
      expect(DebridProviders.capabilities('local').cacheCheck, isFalse);
    });
  });

  group('branding', () {
    test('every registered provider has brand ink', () {
      for (final provider in DebridProviders.all) {
        final brand = debridBrandFor(provider.id);
        expect(brand, isNot(same(debridBrandFallback)), reason: provider.id);
        expect(brand.gradient, hasLength(2));
      }
    });

    test('unknown sources fall back instead of throwing', () {
      expect(debridBrandFor('local'), same(debridBrandFallback));
      expect(debridBrandFor(null), same(debridBrandFallback));
    });

    test('short codes are two letters and unique', () {
      final codes = DebridProviders.all.map((p) => p.shortCode).toList();
      expect(codes.toSet(), hasLength(codes.length));
      for (final code in codes) {
        expect(code, hasLength(2));
      }
    });
  });
}
