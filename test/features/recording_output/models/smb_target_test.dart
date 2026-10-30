import 'dart:convert';

import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmbTarget.isComplete', () {
    test('needs host and share', () {
      expect(const SmbTarget().isComplete, isFalse);
      expect(const SmbTarget(host: 'nas').isComplete, isFalse);
      expect(const SmbTarget(share: 'rec').isComplete, isFalse);
      expect(const SmbTarget(host: 'nas', share: 'rec').isComplete, isTrue);
    });

    test('blank values and slashes in share are incomplete', () {
      expect(const SmbTarget(host: '  ', share: 'rec').isComplete, isFalse);
      expect(const SmbTarget(host: 'nas', share: ' ').isComplete, isFalse);
      expect(const SmbTarget(host: 'nas', share: 'a/b').isComplete, isFalse);
      expect(const SmbTarget(host: 'nas', share: r'a\b').isComplete, isFalse);
    });
  });

  group('folderSegments and remotePathFor', () {
    test('normalises separators, blanks, dot segments', () {
      const t = SmbTarget(folder: r' \TV\ /./..// Recordings ');
      expect(t.folderSegments, ['TV', 'Recordings']);
      expect(t.remotePathFor('a.ts'), 'TV/Recordings/a.ts');
    });

    test('no folder writes to the share root', () {
      expect(const SmbTarget().folderSegments, isEmpty);
      expect(const SmbTarget(folder: '/').remotePathFor('a.ts'), 'a.ts');
    });
  });

  group('displayAddress', () {
    test('uses backslashes', () {
      expect(
        const SmbTarget(host: 'nas', share: 'rec').displayAddress,
        r'\\nas\rec',
      );
      expect(
        const SmbTarget(
          host: 'nas',
          share: 'rec',
          folder: 'TV/Shows',
        ).displayAddress,
        r'\\nas\rec\TV\Shows',
      );
    });

    test('empty when incomplete', () {
      expect(const SmbTarget(host: 'nas').displayAddress, '');
    });
  });

  group('parseAddress', () {
    test('smb url', () {
      final t = SmbTarget.parseAddress('smb://nas.local/media/TV/Rec')!;
      expect(t.host, 'nas.local');
      expect(t.share, 'media');
      expect(t.folder, 'TV/Rec');
    });

    test('UNC path', () {
      final t = SmbTarget.parseAddress(r'\\192.168.1.5\rec\live')!;
      expect(t.host, '192.168.1.5');
      expect(t.share, 'rec');
      expect(t.folder, 'live');
    });

    test('double slash and bare forms', () {
      expect(
        SmbTarget.parseAddress('//nas/rec'),
        const SmbTarget(host: 'nas', share: 'rec'),
      );
      expect(
        SmbTarget.parseAddress(' nas/rec/a/b/ '),
        const SmbTarget(host: 'nas', share: 'rec', folder: 'a/b'),
      );
    });

    test('scheme is case-insensitive', () {
      expect(SmbTarget.parseAddress('SMB://nas/rec')?.host, 'nas');
    });

    test('missing host or share is null', () {
      expect(SmbTarget.parseAddress(''), isNull);
      expect(SmbTarget.parseAddress('smb://'), isNull);
      expect(SmbTarget.parseAddress('smb://nas'), isNull);
      expect(SmbTarget.parseAddress(r'\\nas\'), isNull);
    });

    test('other fields keep defaults', () {
      final t = SmbTarget.parseAddress('nas/rec')!;
      expect(t.enabled, isFalse);
      expect(t.user, '');
      expect(t.domain, '');
      expect(t.deleteLocalAfterUpload, isFalse);
    });
  });

  group('json', () {
    const full = SmbTarget(
      enabled: true,
      host: 'nas',
      share: 'rec',
      folder: 'TV',
      user: 'me',
      domain: 'WORK',
      deleteLocalAfterUpload: true,
    );

    test('round trip', () {
      expect(SmbTarget.decode(full.encode()), full);
      expect(SmbTarget.fromJson(full.toJson()), full);
    });

    test('exact keys', () {
      expect(full.toJson().keys.toSet(), {
        'enabled',
        'host',
        'share',
        'folder',
        'user',
        'domain',
        'deleteLocalAfterUpload',
        'recordDirect',
      });
      expect(jsonDecode(full.encode()), full.toJson());
    });

    test('tolerant decode', () {
      expect(SmbTarget.decode(null), const SmbTarget());
      expect(SmbTarget.decode(''), const SmbTarget());
      expect(SmbTarget.decode('{nope'), const SmbTarget());
      expect(SmbTarget.decode('[1,2]'), const SmbTarget());
      expect(SmbTarget.fromJson(42), const SmbTarget());
      expect(
        SmbTarget.fromJson({'host': 'nas', 'share': 7, 'enabled': 'yes'}),
        const SmbTarget(host: 'nas'),
      );
    });
  });

  test('copyWith and equality', () {
    const a = SmbTarget(host: 'nas', share: 'rec');
    final b = a.copyWith(enabled: true, user: 'u');
    expect(
      b,
      const SmbTarget(enabled: true, host: 'nas', share: 'rec', user: 'u'),
    );
    expect(a.copyWith(), a);
    expect(a.hashCode, const SmbTarget(host: 'nas', share: 'rec').hashCode);
    expect(a == b, isFalse);
  });

  group('recordDirect', () {
    test('is on for a new target and for one saved before it existed', () {
      expect(const SmbTarget().recordDirect, isTrue);
      expect(
        SmbTarget.fromJson({'host': 'nas', 'share': 'tv'}).recordDirect,
        isTrue,
      );
    });

    test('round-trips when turned off', () {
      const off = SmbTarget(host: 'nas', share: 'tv', recordDirect: false);
      expect(SmbTarget.decode(off.encode()), off);
      expect(SmbTarget.decode(off.encode()).recordDirect, isFalse);
    });

    test('writesDirect needs enabled, the option and a complete address', () {
      const ready = SmbTarget(enabled: true, host: 'nas', share: 'tv');
      expect(ready.writesDirect, isTrue);
      expect(ready.copyWith(enabled: false).writesDirect, isFalse);
      expect(ready.copyWith(recordDirect: false).writesDirect, isFalse);
      expect(ready.copyWith(share: '').writesDirect, isFalse);
    });
  });
}
