import 'dart:async';

import 'package:debrify/features/sources/data/source_provider_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reads sequentially in playback order and keeps a configured default',
    () async {
      final reads = <String>[];
      var pendingReads = 0;
      final configuration = await loadSourceProviderConfiguration(
        isConfigured: (provider) async {
          expect(pendingReads, 0);
          pendingReads++;
          reads.add(provider);
          await Future<void>.delayed(Duration.zero);
          pendingReads--;
          return provider != 'alldebrid';
        },
        readDefault: () async {
          reads.add('default');
          return 'premiumize';
        },
      );
      expect(reads, [
        'debrid',
        'torbox',
        'premiumize',
        'alldebrid',
        'pikpak',
        'default',
      ]);
      expect(configuration!.$1, ['debrid', 'torbox', 'premiumize', 'pikpak']);
      expect(configuration.$2, 'premiumize');
      expect(() => configuration.$1.add('other'), throwsUnsupportedError);
    },
  );

  test('no configured providers avoids reading the saved default', () async {
    final configuration = await loadSourceProviderConfiguration(
      isConfigured: (_) async => false,
      readDefault: () => throw StateError('unexpected default read'),
    );
    expect(configuration, isNotNull);
    expect(configuration!.$1, isEmpty);
    expect(configuration.$2, isNull);
  });

  for (final preferred in ['none', 'debrid', 'TORBOX']) {
    test(
      'unconfigured or case-mismatched default $preferred remains unset',
      () async {
        final configuration = await loadSourceProviderConfiguration(
          isConfigured: (provider) async => provider == 'torbox',
          readDefault: () async => preferred,
        );
        expect(configuration!.$1, ['torbox']);
        expect(configuration.$2, isNull);
      },
    );
  }

  test('retirement before loading prevents all reads', () async {
    expect(
      await loadSourceProviderConfiguration(
        canContinue: () => false,
        isConfigured: (_) => throw StateError('unexpected credential read'),
        readDefault: () => throw StateError('unexpected default read'),
      ),
      isNull,
    );
  });

  test(
    'retirement during a credential read stops the next provider and default',
    () async {
      var active = true;
      final first = Completer<bool>();
      final reads = <String>[];
      final work = loadSourceProviderConfiguration(
        canContinue: () => active,
        isConfigured: (provider) {
          reads.add(provider);
          return first.future;
        },
        readDefault: () => throw StateError('stale default read'),
      );
      expect(reads, ['debrid']);
      active = false;
      first.complete(true);
      expect(await work, isNull);
      expect(reads, ['debrid']);
    },
  );

  test(
    'retirement while reading the default discards the entire configuration',
    () async {
      var active = true;
      final entered = Completer<void>();
      final preferred = Completer<String>();
      final work = loadSourceProviderConfiguration(
        canContinue: () => active,
        isConfigured: (_) async => true,
        readDefault: () {
          entered.complete();
          return preferred.future;
        },
      );
      await entered.future;
      active = false;
      preferred.complete('torbox');
      expect(await work, isNull);
    },
  );

  for (final retired in [false, true]) {
    test(
      'read error ${retired ? 'is discarded after retirement' : 'propagates while current without retry'}',
      () async {
        var active = true;
        var reads = 0;
        final credential = Completer<bool>();
        final work = loadSourceProviderConfiguration(
          canContinue: () => active,
          isConfigured: (_) {
            reads++;
            return credential.future;
          },
          readDefault: () => throw StateError('unexpected default read'),
        );
        final checked = expectLater(
          work,
          retired ? completion(isNull) : throwsStateError,
        );
        active = !retired;
        credential.completeError(StateError('read failed'));
        await checked;
        expect(reads, 1);
      },
    );
  }
}
