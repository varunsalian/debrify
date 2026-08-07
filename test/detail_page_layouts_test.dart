import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/screens/settings/detail_page_style_page.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/detail/detail_style.dart';

void main() {
  group('resolveDetailSize', () {
    test('television always wins, whatever the geometry', () {
      expect(
        resolveDetailSize(isTelevision: true, size: const Size(960, 540)),
        DetailSize.tv,
      );
      expect(
        resolveDetailSize(isTelevision: true, size: const Size(390, 844)),
        DetailSize.tv,
      );
    });

    test('phone boundary at 560/561 on the SHORT side', () {
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(560, 900)),
        DetailSize.phone,
      );
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(561, 900)),
        DetailSize.tabletPortrait,
      );
    });

    test('a landscape phone is a phone, not a desktop', () {
      // The bug this guards: shortSide taken as size.width would read 800 here
      // and fall through to desktop.
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(800, 400)),
        DetailSize.phone,
      );
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(900, 450)),
        DetailSize.phone,
      );
    });

    test('portrait tablet boundary at 899/900', () {
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(899, 1200)),
        DetailSize.tabletPortrait,
      );
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(900, 1200)),
        DetailSize.desktop,
      );
    });

    test('landscape desktop', () {
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(1280, 800)),
        DetailSize.desktop,
      );
    });

    test('a square window is treated as portrait', () {
      expect(
        resolveDetailSize(isTelevision: false, size: const Size(700, 700)),
        DetailSize.tabletPortrait,
      );
    });
  });

  group('detail page style pref', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('unset reads classic', () async {
      expect(await StorageService.getDetailPageStyle(), 'classic');
      expect(StorageService.detailPageStyleCached, 'classic');
    });

    test('a known value round-trips and updates the sync cache', () async {
      await StorageService.setDetailPageStyle('marquee');
      expect(StorageService.detailPageStyleCached, 'marquee');
      expect(await StorageService.getDetailPageStyle(), 'marquee');
    });

    test('an unknown value is coerced on WRITE', () async {
      await StorageService.setDetailPageStyle('nonsense');
      expect(await StorageService.getDetailPageStyle(), 'classic');
    });

    test('an unknown stored value is coerced on READ', () async {
      SharedPreferences.setMockInitialValues({
        'detail_page_style': 'nonsense',
      });
      expect(await StorageService.getDetailPageStyle(), 'classic');
    });

    test('storage accepts every style, including ones not yet drawable', () {
      // A choice written by a NEWER build must survive a downgrade rather than
      // be rewritten the first time an older build reads it.
      for (final s in const [
        'classic',
        'marquee',
        'dossier',
        'broadsheet',
        'stage',
        'filmstrip',
        'console',
      ]) {
        expect(StorageService.kDetailPageStyles.contains(s), isTrue);
      }
    });
  });

  group('effectiveDetailPageStyle', () {
    test('passes through a style this build ships', () {
      for (final s in kDetailPageStylesShipped) {
        expect(effectiveDetailPageStyle(s), s);
      }
    });

    test('narrows a stored style this build cannot draw', () {
      final unshipped = StorageService.kDetailPageStyles
          .difference(kDetailPageStylesShipped);
      for (final s in unshipped) {
        expect(
          effectiveDetailPageStyle(s),
          'classic',
          reason: '$s is not shipped, so dispatch and the label must say Classic',
        );
      }
    });

    test('the row label follows the effective style, never the raw one', () {
      expect(detailPageStyleLabel('classic'), 'Classic');
      for (final s in StorageService.kDetailPageStyles
          .difference(kDetailPageStylesShipped)) {
        expect(detailPageStyleLabel(s), 'Classic');
      }
    });

    test('every shipped style has a picker entry', () {
      for (final s in kDetailPageStylesShipped) {
        expect(
          kDetailPageStyleChoices.any((c) => c.value == s),
          isTrue,
          reason: '$s is shipped but has no label/description',
        );
      }
    });

    test('every picker entry is a value storage will persist', () {
      for (final c in kDetailPageStyleChoices) {
        expect(StorageService.kDetailPageStyles.contains(c.value), isTrue);
      }
    });
  });
}
