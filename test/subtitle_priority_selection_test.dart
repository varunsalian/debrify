import 'dart:async';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/utils/subtitle_priority_selection.dart';
import 'package:flutter_test/flutter_test.dart';

AddonSubtitleSlot slot(String id, {bool loading = false, String? language}) =>
    AddonSubtitleSlot(
      addonId: id,
      addonName: id,
      status: loading ? AddonSubtitleStatus.loading : AddonSubtitleStatus.ok,
      subtitles: [
        if (language != null)
          StremioSubtitle(
            id: '$id-sub',
            url: 'https://example.test/$id.srt',
            lang: language,
            source: id,
          ),
      ],
    );

void main() {
  const order = ['addon:a', 'embedded', 'addon:b'];
  late List<String> applied;
  late bool finalized;
  late bool current;

  Future<SubtitlePriorityResult?> select(
    List<AddonSubtitleSlot> slots, {
    bool discoveryReady = true,
    String? language,
  }) async {
    final result = await selectSubtitleBySourcePriority(
      saved: order,
      language: language,
      slots: slots,
      discoveryReady: discoveryReady,
      isCurrent: () => current && !finalized,
      tryEmbedded: () async {
        applied.add('embedded');
        return true;
      },
      tryAddon: (sub) async {
        applied.add(sub.source);
        return true;
      },
    );
    if (result != null && !result.provisional) finalized = true;
    return result;
  }

  setUp(() {
    applied = [];
    finalized = false;
    current = true;
  });

  test(
    'late metadata replaces provisional embedded with preferred addon',
    () async {
      final initial = await select([], discoveryReady: false);
      expect(initial!.provisional, isTrue);
      expect(finalized, isFalse);
      final resolved = await select([slot('a', language: 'eng')]);
      expect(resolved!.addon!.source, 'a');
      expect(applied, ['embedded', 'a']);
      expect(finalized, isTrue);
    },
  );

  test(
    'embedded fallback does not wait for lower-priority addon timeout',
    () async {
      final result = await select([slot('a'), slot('b', loading: true)]);
      expect(result, isNotNull);
      expect(result!.addon, isNull);
      expect(result.provisional, isFalse);
      expect(applied, ['embedded']);
    },
  );

  test(
    'preferred addon can apply while lower-priority addon is still loading',
    () async {
      final result = await select([
        slot('a', language: 'eng'),
        slot('b', loading: true),
      ]);
      expect(result!.addon!.source, 'a');
      expect(applied, ['a']);
    },
  );

  test(
    'higher-priority loading source blocks faster lower-priority candidates',
    () async {
      expect(
        await select([slot('a', loading: true), slot('b', language: 'eng')]),
        isNull,
      );
      expect(applied, isEmpty);
      await select([slot('a'), slot('b', language: 'eng')]);
      expect(applied, ['embedded']);
    },
  );

  test(
    'language mismatch falls back without waiting for lower-priority source',
    () async {
      await select([
        slot('a', language: 'spa'),
        slot('b', loading: true),
      ], language: 'en');
      expect(applied, ['embedded']);
    },
  );

  test(
    'manual selection and Off are preserved after provisional fallback',
    () async {
      await select([], discoveryReady: false);
      current = false; // The user picked a subtitle during metadata discovery.
      expect(await select([slot('a', language: 'eng')]), isNull);
      current = true;
      expect(
        await select([slot('a', language: 'eng')], language: 'off'),
        isNull,
      );
      expect(applied, ['embedded']);
    },
  );

  test(
    'metadata update arriving during provisional apply is not dropped',
    () async {
      final queue = SubtitlePrioritySelectionQueue();
      final entered = Completer<void>();
      final release = Completer<void>();
      Future<void> apply(SubtitlePriorityUpdate update) async {
        final result = await selectSubtitleBySourcePriority(
          saved: order,
          language: null,
          slots: update.slots,
          discoveryReady: update.discoveryReady,
          isCurrent: () => !finalized,
          tryEmbedded: () async {
            entered.complete();
            await release.future;
            applied.add('embedded');
            return true;
          },
          tryAddon: (sub) async {
            applied.add(sub.source);
            return true;
          },
        );
        if (result != null && !result.provisional) finalized = true;
      }

      final first = queue.submit(
        const SubtitlePriorityUpdate(1, [], discoveryReady: false),
        apply,
      );
      await entered.future;
      final next = queue.submit(
        SubtitlePriorityUpdate(1, [slot('a', language: 'eng')]),
        apply,
      );
      release.complete();
      await Future.wait([first, next]);
      expect(applied, ['embedded', 'a']);
      expect(finalized, isTrue);
    },
  );

  test(
    'new source can select while old generation download is pending',
    () async {
      final queue = SubtitlePrioritySelectionQueue();
      final entered = Completer<void>();
      final release = Completer<void>();
      var activeToken = 1;
      Future<void> apply(SubtitlePriorityUpdate update) async {
        await selectSubtitleBySourcePriority(
          saved: order,
          language: null,
          slots: update.slots,
          discoveryReady: true,
          isCurrent: () => update.token == activeToken,
          tryEmbedded: () async {
            applied.add('embedded');
            return true;
          },
          tryAddon: (sub) async {
            entered.complete();
            await release.future;
            // Same generation check as the player performs after downloading.
            if (update.token != activeToken) return false;
            applied.add(sub.source);
            return true;
          },
        );
      }

      final first = queue.submit(
        SubtitlePriorityUpdate(1, [slot('a', language: 'eng')]),
        apply,
      );
      await entered.future;
      activeToken = 2;
      await queue.submit(SubtitlePriorityUpdate(2, [slot('a')]), apply);
      expect(applied, ['embedded']);
      release.complete();
      await first;
      expect(applied, ['embedded']);
    },
  );
}
