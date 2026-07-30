import 'package:debrify/utils/stremio_tv_debrid_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StremioTvDebridFallback', () {
    test(
      'auto advances from Real-Debrid to TorBox after a null result',
      () async {
        final attempts = <String>[];

        final result = await StremioTvDebridFallback.resolve<String>(
          selected: 'auto',
          attempt: (provider) async {
            attempts.add(provider);
            return provider == 'torbox' ? 'playable-url' : null;
          },
        );

        expect(result, 'playable-url');
        expect(attempts, ['realdebrid', 'torbox']);
      },
    );

    test('an explicitly selected provider remains strict', () async {
      final attempts = <String>[];

      final result = await StremioTvDebridFallback.resolve<String>(
        selected: 'torbox',
        attempt: (provider) async {
          attempts.add(provider);
          return null;
        },
      );

      expect(result, isNull);
      expect(attempts, ['torbox']);
    });

    test('auto never attempts disabled integrations', () async {
      final attempts = <String>[];

      await StremioTvDebridFallback.resolve<String>(
        selected: 'auto',
        canAttempt: (provider) async =>
            provider != 'premiumize' && provider != 'alldebrid',
        attempt: (provider) async {
          attempts.add(provider);
          return null;
        },
      );

      expect(attempts, ['realdebrid', 'torbox', 'pikpak']);
    });

    test(
      'a provider-specific rejection preserves the source for fallback',
      () async {
        final attempts = <String>[];

        final result = await StremioTvDebridFallback.resolve<String>(
          selected: 'auto',
          canAttempt: (provider) async => provider != 'realdebrid',
          attempt: (provider) async {
            attempts.add(provider);
            return provider == 'torbox' ? 'torbox-url' : null;
          },
        );

        expect(result, 'torbox-url');
        expect(attempts, ['torbox']);
      },
    );

    test('cancellation stops automatic failover between providers', () async {
      final attempts = <String>[];
      var cancelled = false;

      final result = await StremioTvDebridFallback.resolve<String>(
        selected: 'auto',
        isCancelled: () => cancelled,
        attempt: (provider) async {
          attempts.add(provider);
          cancelled = true;
          return null;
        },
      );

      expect(result, isNull);
      expect(attempts, ['realdebrid']);
    });

    test('cancellation after a gate prevents the provider attempt', () async {
      final attempts = <String>[];
      var cancelled = false;

      await StremioTvDebridFallback.resolve<String>(
        selected: 'auto',
        isCancelled: () => cancelled,
        canAttempt: (provider) async {
          cancelled = true;
          return true;
        },
        attempt: (provider) async {
          attempts.add(provider);
          return 'unexpected';
        },
      );

      expect(attempts, isEmpty);
    });

    test('memoized async loader batches repeated cache consumers', () async {
      var loadCount = 0;
      final load = StremioTvDebridFallback.memoizeAsync<Set<String>>(() async {
        loadCount++;
        return <String>{'cached-hash'};
      });

      final results = await Future.wait(<Future<Set<String>>>[
        load(),
        load(),
        load(),
      ]);

      expect(loadCount, 1);
      expect(results, everyElement(<String>{'cached-hash'}));
    });

    test('PikPak cleanup prefers a pack root over its selected file', () {
      expect(
        StremioTvDebridFallback.pikPakCleanupRootId(<String, dynamic>{
          'pikpakFolderId': 'folder-root',
          'pikpakFileId': 'selected-child',
        }),
        'folder-root',
      );
    });

    test('PikPak cleanup falls back to a direct file ID', () {
      expect(
        StremioTvDebridFallback.pikPakCleanupRootId(<String, dynamic>{
          'pikpakFileId': 'direct-file',
        }),
        'direct-file',
      );
      expect(
        StremioTvDebridFallback.pikPakCleanupRootId(<String, dynamic>{
          'pikpakFolderId': ' ',
          'pikpakFileId': '',
        }),
        isNull,
      );
    });
  });
}
