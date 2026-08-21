import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_avatar_storage.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/profiles/profile_art.dart';
import 'package:debrify/widgets/profiles/profile_avatar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'avatar_fixtures.dart';

void main() {
  late Directory root;
  const profileId = 'admin-v1';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('avatar-view-');
    AppStorage.debugOverride(documents: root);
  });

  tearDown(() async {
    AppStorage.debugReset();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Widget harness({
    required String? avatarKey,
    bool focused = false,
    bool allowAnimation = true,
    bool animateWhenIdle = false,
    UserProfileRole role = UserProfileRole.admin,
    String name = 'Meera',
  }) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 120,
        height: 120,
        child: ProfileAvatarView(
          profileId: profileId,
          avatarKey: avatarKey,
          role: role,
          name: name,
          focused: focused,
          allowAnimation: allowAnimation,
          animateWhenIdle: animateWhenIdle,
        ),
      ),
    ),
  );

  /// The avatar resolves its file with real IO in `initState`, which the test
  /// binding's fake clock will not advance — so anything file-backed has to be
  /// pumped inside `runAsync`. (`pumpAndSettle` here just waits out its
  /// ten-minute timeout.)
  Future<void> pumpResolved(WidgetTester tester, Widget widget) async {
    // `pump` must stay outside `runAsync` — driving the test scheduler from
    // inside it deadlocks. So: pump to mount, let real IO run, pump again to
    // rebuild with the resolved file.
    await tester.pumpWidget(widget);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
  }

  /// `willChange` mirrors the controller, so it is the observable form of
  /// "is this avatar animating right now".
  bool artIsAnimating(WidgetTester tester) => tester
      .widget<CustomPaint>(find.byKey(ProfileAvatarView.artPaintKey))
      .willChange;

  group('focus-only animation', () {
    testWidgets('unfocused art holds still', (tester) async {
      await tester.pumpWidget(harness(avatarKey: 'art:aurora'));
      expect(artIsAnimating(tester), isFalse);
    });

    testWidgets('focused art animates', (tester) async {
      await tester.pumpWidget(harness(avatarKey: 'art:aurora', focused: true));
      expect(artIsAnimating(tester), isTrue);
      // Unmount so the repeating ticker does not outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('static art never starts a ticker, even focused', (
      tester,
    ) async {
      // `dusk` declares animated:false — it must not burn a ticker on TV.
      expect(ProfileArtRegistry.byId('dusk')!.animated, isFalse);
      await tester.pumpWidget(harness(avatarKey: 'art:dusk', focused: true));
      expect(artIsAnimating(tester), isFalse);
    });

    testWidgets('losing focus stops the ticker', (tester) async {
      await tester.pumpWidget(harness(avatarKey: 'art:aurora', focused: true));
      expect(artIsAnimating(tester), isTrue);
      await tester.pumpWidget(harness(avatarKey: 'art:aurora'));
      expect(artIsAnimating(tester), isFalse);
    });

    testWidgets('the animation switch overrides focus', (tester) async {
      await tester.pumpWidget(
        harness(avatarKey: 'art:aurora', focused: true, allowAnimation: false),
      );
      expect(artIsAnimating(tester), isFalse);
    });
  });

  group('GIF avatars', () {
    Future<String> writeGif() async {
      final directory = ProfileAvatarStorage.directoryIn(root, profileId);
      await directory.create(recursive: true);
      await File(
        p.join(directory.path, 'anim.gif'),
      ).writeAsBytes(tinyGif, flush: true);
      return 'file:avatars/anim.gif#1E8E7E';
    }

    testWidgets('unfocused shows a still frame, not a live decoder', (
      tester,
    ) async {
      // Real IO must run inside `runAsync`; in the fake-async test zone a
      // plain `await File.writeAsBytes` never completes.
      final key = (await tester.runAsync(writeGif))!;
      await pumpResolved(tester, harness(avatarKey: key));

      expect(
        find.byType(Image),
        findsNothing,
        reason: 'an unfocused GIF must not hold an animating decoder',
      );
      // The still-frame branch is the contract; whether its first frame has
      // finished decoding yet is timing, and the placeholder colour is a
      // deliberate intermediate state.
      expect(find.byKey(ProfileAvatarView.stillFrameKey), findsOneWidget);
    });

    testWidgets('focused swaps to the animated image', (tester) async {
      final key = (await tester.runAsync(writeGif))!;
      await pumpResolved(tester, harness(avatarKey: key, focused: true));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(ProfileAvatarView.stillFrameKey), findsNothing);
    });

    testWidgets('animateWhenIdle plays the GIF without focus (touch)', (
      tester,
    ) async {
      final key = (await tester.runAsync(writeGif))!;
      await pumpResolved(
        tester,
        harness(avatarKey: key, animateWhenIdle: true),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(ProfileAvatarView.stillFrameKey), findsNothing);
    });

    testWidgets('the animation switch still outranks animateWhenIdle', (
      tester,
    ) async {
      final key = (await tester.runAsync(writeGif))!;
      await pumpResolved(
        tester,
        harness(avatarKey: key, animateWhenIdle: true, allowAnimation: false),
      );
      expect(find.byKey(ProfileAvatarView.stillFrameKey), findsOneWidget);
    });
  });

  group('bundled GIF avatars', () {
    testWidgets('unfocused bundled art holds its first frame', (tester) async {
      await tester.pumpWidget(harness(avatarKey: 'art:snack_popcorn'));

      expect(find.byType(Image), findsNothing);
      expect(find.byKey(ProfileAvatarView.stillFrameKey), findsOneWidget);
    });

    testWidgets('focused bundled art animates', (tester) async {
      await tester.pumpWidget(
        harness(avatarKey: 'art:snack_popcorn', focused: true),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(ProfileAvatarView.stillFrameKey), findsNothing);
    });

    test('declares a stable wash colour and bundled asset', () {
      final art = ProfileArtRegistry.byId('snack_popcorn');
      expect(art?.isAsset, isTrue);
      expect(art?.assetPath, endsWith('snack_popcorn.gif'));
      expect(
        ProfileAvatarView.washColor('art:snack_popcorn', UserProfileRole.admin),
        art?.color,
      );
    });
  });

  group('the missing-file floor', () {
    testWidgets('a key with no file renders the initial, never an error', (
      tester,
    ) async {
      // Exactly the tvOS restore case: the key survives, the bytes do not.
      await pumpResolved(
        tester,
        harness(avatarKey: 'file:avatars/gone.gif#4A90D9', name: 'Meera'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('an unparseable key falls back to the role icon', (
      tester,
    ) async {
      await tester.pumpWidget(harness(avatarKey: 'file:../../escape.png'));
      expect(tester.takeException(), isNull);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('a null key renders the role icon', (tester) async {
      await tester.pumpWidget(
        harness(avatarKey: null, role: UserProfileRole.child),
      );
      expect(find.byIcon(Icons.child_care_rounded), findsOneWidget);
    });
  });

  testWidgets('a key change during file resolution resolves the new file', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = ProfileAvatarStorage.directoryIn(root, profileId);
      await directory.create(recursive: true);
      final bytes = await paintPng(size: 24);
      await File(p.join(directory.path, 'a.png')).writeAsBytes(bytes);
      await File(p.join(directory.path, 'b.png')).writeAsBytes(bytes);
    });

    await tester.pumpWidget(harness(avatarKey: 'file:avatars/a.png'));
    await tester.pumpWidget(harness(avatarKey: 'file:avatars/b.png'));
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('M'), findsNothing);
  });

  testWidgets('a parent refresh resolves bytes repaired under the same key', (
    tester,
  ) async {
    const key = 'file:avatars/repaired.png#4A90D9';
    await pumpResolved(tester, harness(avatarKey: key));
    expect(find.text('M'), findsOneWidget);

    await tester.runAsync(() async {
      final directory = ProfileAvatarStorage.directoryIn(root, profileId);
      await directory.create(recursive: true);
      await File(
        p.join(directory.path, 'repaired.png'),
      ).writeAsBytes(await paintPng(size: 24), flush: true);
    });
    // The profile model did not change; this is the roster refresh a restore or
    // same-content ingest produces after repairing the missing file.
    await pumpResolved(tester, harness(avatarKey: key));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('M'), findsNothing);
  });

  testWidgets('cache eviction does not dispose images held by mounted tiles', (
    tester,
  ) async {
    final keys = await tester.runAsync(() async {
      final directory = ProfileAvatarStorage.directoryIn(root, profileId);
      await directory.create(recursive: true);
      final result = <String>[];
      for (var i = 0; i < 33; i++) {
        final name = 'anim-$i.gif';
        await File(p.join(directory.path, name)).writeAsBytes(tinyGif);
        result.add('file:avatars/$name');
      }
      return result;
    });
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: <Widget>[
            for (final key in keys!)
              SizedBox.square(
                dimension: 80,
                child: ProfileAvatarView(
                  profileId: profileId,
                  avatarKey: key,
                  role: UserProfileRole.admin,
                  name: 'Meera',
                ),
              ),
          ],
        ),
      ),
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(debugStillFrameCacheSize(), lessThanOrEqualTo(32));
    expect(tester.takeException(), isNull);
  });

  group('washColor never reads a file', () {
    test('art declares its own colour', () {
      expect(
        ProfileAvatarView.washColor('art:aurora', UserProfileRole.admin),
        ProfileArtRegistry.byId('aurora')!.color,
      );
    });

    test('an image carries its colour in the key', () {
      expect(
        ProfileAvatarView.washColor(
          'file:avatars/a.gif#4A90D9',
          UserProfileRole.admin,
        ),
        const Color(0xFF4A90D9),
      );
    });

    test('anything else falls back by role', () {
      final admin = ProfileAvatarView.washColor(null, UserProfileRole.admin);
      final child = ProfileAvatarView.washColor(null, UserProfileRole.child);
      expect(admin, isNot(child));
      expect(
        ProfileAvatarView.washColor(
          'file:avatars/a.gif',
          UserProfileRole.member,
        ),
        ProfileAvatarView.washColor(null, UserProfileRole.member),
      );
    });
  });

  test('every registered art id is unique and resolvable', () {
    final ids = ProfileArtRegistry.all.map((a) => a.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final art in ProfileArtRegistry.all) {
      expect(ProfileArtRegistry.byId(art.id), same(art));
    }
  });
}
