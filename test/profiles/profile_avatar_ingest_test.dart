import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/services/profiles/profile_avatar_ingest.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/services/profiles/profile_avatar_storage.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'avatar_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  const profileId = 'admin-v1';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('avatar-ingest-');
    AppStorage.debugOverride(documents: root);
  });

  tearDown(() async {
    AppStorage.debugReset();
    ProfileAvatarPolicy.debugSetUserImagesSupported(null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a static image is stored as PNG with a wash colour', () async {
    final avatar = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: await paintPng(size: 64),
    );

    expect(avatar.kind, ProfileAvatarKind.image);
    expect(avatar.id, endsWith('.png'));
    expect(avatar.isAnimatedImage, isFalse);
    expect(avatar.dominantColor, isNotNull);

    final file = await ProfileAvatarStorage.fileFor(profileId, avatar);
    expect(await file.exists(), isTrue);
    expect(ProfileAvatar.tryParse(avatar.format()), avatar);
  });

  test('the wash colour resembles the picture', () async {
    final avatar = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: await paintPng(size: 64, color: const Color(0xFF3366CC)),
    );
    final colour = avatar.dominantColor!;
    final r = (colour >> 16) & 0xFF;
    final g = (colour >> 8) & 0xFF;
    final b = colour & 0xFF;
    // Blue-dominant, and not the grey an averaging implementation produces.
    expect(
      b,
      greaterThan(r + 40),
      reason: 'colour was ${colour.toRadixString(16)}',
    );
    expect(b, greaterThan(g));
  });

  test('an oversized image is downscaled, not refused', () async {
    final avatar = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: await paintPng(size: 2000),
    );
    final file = await ProfileAvatarStorage.fileFor(profileId, avatar);
    final bytes = await file.readAsBytes();
    expect(bytes.length, lessThanOrEqualTo(ProfileAvatarIngest.maxBytes));

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    addTearDown(descriptor.dispose);
    expect(
      descriptor.width,
      lessThanOrEqualTo(ProfileAvatarIngest.maxDimension),
    );
    expect(
      descriptor.height,
      lessThanOrEqualTo(ProfileAvatarIngest.maxDimension),
    );
  });

  test(
    'a GIF is stored byte-for-byte — never flattened to one frame',
    () async {
      final avatar = await ProfileAvatarIngest.ingest(
        profileId: profileId,
        bytes: tinyGif,
      );

      expect(avatar.id, endsWith('.gif'));
      expect(avatar.isAnimatedImage, isTrue);
      final file = await ProfileAvatarStorage.fileFor(profileId, avatar);
      expect(
        await file.readAsBytes(),
        tinyGif,
        reason: 'transcoding a GIF would silently drop its animation',
      );
    },
  );

  test(
    'an over-large GIF is refused with a reason the user can act on',
    () async {
      final huge = Uint8List.fromList(<int>[
        ...tinyGif,
        ...List<int>.filled(ProfileAvatarIngest.maxBytes + 1, 0),
      ]);
      await expectLater(
        ProfileAvatarIngest.ingest(profileId: profileId, bytes: huge),
        throwsA(
          isA<ProfileAvatarRejected>().having(
            (e) => e.message,
            'message',
            allOf(contains('GIF'), contains('limit')),
          ),
        ),
      );
    },
  );

  test('a non-image is refused by its bytes, not its name', () async {
    await expectLater(
      ProfileAvatarIngest.ingest(
        profileId: profileId,
        bytes: Uint8List.fromList('MZ not an image at all'.codeUnits),
      ),
      throwsA(isA<ProfileAvatarRejected>()),
    );
  });

  test('an empty file is refused', () async {
    await expectLater(
      ProfileAvatarIngest.ingest(profileId: profileId, bytes: Uint8List(0)),
      throwsA(isA<ProfileAvatarRejected>()),
    );
  });

  test('replacing an avatar leaves only the new file', () async {
    final first = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: await paintPng(size: 32, color: const Color(0xFFCC3333)),
    );
    final second = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: tinyGif,
    );

    expect(first.id, isNot(second.id));
    final directory = await ProfileAvatarStorage.directoryFor(profileId);
    final remaining = await directory.list().toList();
    expect(remaining, hasLength(1));
    expect(remaining.single.path, endsWith('.gif'));
  });

  test('a candidate write does not prune the committed avatar', () async {
    final first = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: await paintPng(size: 32, color: const Color(0xFFCC3333)),
    );
    final candidate = await ProfileAvatarIngest.prepare(tinyGif);

    await ProfileAvatarIngest.writeCandidate(
      profileId: profileId,
      prepared: candidate,
    );

    final oldFile = await ProfileAvatarStorage.fileFor(profileId, first);
    final newFile = await ProfileAvatarStorage.fileFor(
      profileId,
      candidate.avatar,
    );
    expect(await oldFile.exists(), isTrue);
    expect(await newFile.exists(), isTrue);

    await ProfileAvatarIngest.discardCandidate(
      profileId: profileId,
      candidate: candidate.avatar,
      preserve: first,
    );
    expect(await oldFile.exists(), isTrue);
    expect(await newFile.exists(), isFalse);
  });

  test('committing an art selection removes the former photo', () async {
    await ProfileAvatarIngest.ingest(profileId: profileId, bytes: tinyGif);

    await ProfileAvatarIngest.commit(
      profileId: profileId,
      avatarKey: 'art:aurora',
    );

    final directory = await ProfileAvatarStorage.directoryFor(profileId);
    expect(await directory.exists(), isFalse);
  });

  test('re-ingesting the same picture reuses one file', () async {
    final bytes = await paintPng(size: 32);
    final a = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: bytes,
    );
    final b = await ProfileAvatarIngest.ingest(
      profileId: profileId,
      bytes: bytes,
    );
    expect(a.id, b.id, reason: 'content-addressed names dedupe');
  });

  test('an existing content address is never truncated in place', () async {
    final prepared = await ProfileAvatarIngest.prepare(
      await paintPng(size: 32),
    );
    final file = await ProfileAvatarStorage.fileFor(profileId, prepared.avatar);
    await file.parent.create(recursive: true);
    final sentinel = Uint8List.fromList(<int>[9, 8, 7, 6]);
    await file.writeAsBytes(sentinel, flush: true);

    await expectLater(
      ProfileAvatarIngest.writeCandidate(
        profileId: profileId,
        prepared: prepared,
      ),
      throwsStateError,
    );

    expect(await file.readAsBytes(), sentinel);
  });

  test('tvOS refuses user images at the single policy boundary', () async {
    ProfileAvatarPolicy.debugSetUserImagesSupported(false);
    await expectLater(
      ProfileAvatarIngest.ingest(profileId: profileId, bytes: tinyGif),
      throwsA(isA<ProfileAvatarRejected>()),
    );
    final directory = await ProfileAvatarStorage.directoryFor(profileId);
    expect(await directory.exists(), isFalse);
  });
}
