import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('legacy keys', () {
    test('every shipped icon key still parses', () {
      for (final id in ProfileAvatar.legacyIconIds) {
        final avatar = ProfileAvatar.tryParse(id);
        expect(avatar?.kind, ProfileAvatarKind.icon, reason: id);
        expect(avatar?.id, id);
      }
    });

    test('an unknown bare key degrades to null, never throws', () {
      expect(ProfileAvatar.tryParse('wizard'), isNull);
      expect(ProfileAvatar.tryParse(''), isNull);
      expect(ProfileAvatar.tryParse(null), isNull);
    });
  });

  group('art keys', () {
    test('round-trips', () {
      final avatar = ProfileAvatar.tryParse('art:aurora');
      expect(avatar?.kind, ProfileAvatarKind.art);
      expect(avatar?.id, 'aurora');
      expect(avatar?.format(), 'art:aurora');
    });

    test('rejects an id that could not name a painter', () {
      expect(ProfileAvatar.tryParse('art:'), isNull);
      expect(ProfileAvatar.tryParse('art:Aurora'), isNull);
      expect(ProfileAvatar.tryParse('art:../aurora'), isNull);
    });
  });

  group('image keys', () {
    test('round-trips with a colour', () {
      const key = 'file:avatars/a1b2.gif#4A90D9';
      final avatar = ProfileAvatar.tryParse(key);
      expect(avatar?.kind, ProfileAvatarKind.image);
      expect(avatar?.id, 'avatars/a1b2.gif');
      expect(avatar?.dominantColor, 0x4A90D9);
      expect(avatar?.format(), key);
    });

    test('round-trips without a colour', () {
      final avatar = ProfileAvatar.tryParse('file:avatars/a1b2.png');
      expect(avatar?.dominantColor, isNull);
      expect(avatar?.format(), 'file:avatars/a1b2.png');
    });

    test('only a GIF counts as animated', () {
      expect(
        ProfileAvatar.tryParse('file:avatars/a.gif')!.isAnimatedImage,
        isTrue,
      );
      expect(
        ProfileAvatar.tryParse('file:avatars/a.png')!.isAnimatedImage,
        isFalse,
      );
      expect(ProfileAvatar.tryParse('art:aurora')!.isAnimatedImage, isFalse);
    });

    test('a malformed colour rejects the whole key', () {
      expect(ProfileAvatar.tryParse('file:avatars/a.png#GGGGGG'), isNull);
      expect(ProfileAvatar.tryParse('file:avatars/a.png#4A90'), isNull);
    });
  });

  // A `file:` key arrives from untrusted portable packages, so these are the
  // cases that must never yield a resolvable path.
  group('hostile keys are refused', () {
    const hostile = <String>[
      'file:../../../etc/passwd',
      'file:avatars/../../escape.png',
      'file:/etc/passwd',
      r'file:C:\windows\system32\a.png',
      r'file:avatars\..\escape.png',
      'file:nested/avatars/a.png',
      'file:avatars/deeper/a.png',
      'file:a.png',
      'file:avatars/',
      'file:avatars/a.exe',
      'file:avatars/a.png.exe',
      'file:avatars/.png',
      'file:avatars/a b.png',
    ];

    for (final key in hostile) {
      test('rejects $key', () => expect(ProfileAvatar.tryParse(key), isNull));
    }

    test('rejects an over-long key', () {
      final long = 'file:avatars/${'a' * 300}.png';
      expect(ProfileAvatar.tryParse(long), isNull);
    });

    test('the constructor refuses what the parser refuses', () {
      expect(
        () => ProfileAvatar.image('../escape.png'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('parse(format(x)) == x for every kind', () {
    final avatars = <ProfileAvatar>[
      const ProfileAvatar.icon('movie'),
      const ProfileAvatar.art('aurora'),
      ProfileAvatar.image('avatars/a1b2.gif', dominantColor: 0x0A0B0C),
      ProfileAvatar.image('avatars/a1b2.webp'),
    ];
    for (final avatar in avatars) {
      expect(
        ProfileAvatar.tryParse(avatar.format()),
        avatar,
        reason: '$avatar',
      );
    }
  });
}
