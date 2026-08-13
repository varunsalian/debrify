import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SecretVault.debugReset(deviceIdOverride: 'test-device-1');
    SharedPreferences.setMockInitialValues({});
  });

  group('seal/open', () {
    test('round-trips a value', () async {
      final sealed = await SecretVault.seal('rd_key_abc123');
      expect(sealed, startsWith(SecretVault.prefix));
      expect(await SecretVault.open(sealed), 'rd_key_abc123');
    });

    test('round-trips the empty string', () async {
      final sealed = await SecretVault.seal('');
      expect(await SecretVault.open(sealed), '');
    });

    test('null passes through', () async {
      expect(await SecretVault.open(null), isNull);
    });

    test('legacy plaintext is returned verbatim', () async {
      expect(await SecretVault.open('plain-api-key'), 'plain-api-key');
    });

    test('distinct nonces per seal', () async {
      final a = await SecretVault.seal('same');
      final b = await SecretVault.seal('same');
      expect(a, isNot(b));
      expect(await SecretVault.open(a), 'same');
      expect(await SecretVault.open(b), 'same');
    });

    test('tampered ciphertext opens to null', () async {
      final sealed = await SecretVault.seal('secret');
      // Flip a character in the middle of the base64 body.
      final i = sealed.length ~/ 2;
      final flipped = sealed[i] == 'A' ? 'B' : 'A';
      final tampered =
          sealed.substring(0, i) + flipped + sealed.substring(i + 1);
      expect(await SecretVault.open(tampered), isNull);
    });

    test('malformed envelopes open to null, never throw', () async {
      expect(await SecretVault.open('enc1:not-base64!!'), isNull);
      expect(await SecretVault.open('enc1:'), isNull);
      // Valid base64 but shorter than nonce+tag.
      expect(await SecretVault.open('enc1:AAAA'), isNull);
    });

    test('different device ID opens to null', () async {
      final sealed = await SecretVault.seal('bound-secret');
      SecretVault.debugReset(deviceIdOverride: 'other-device');
      expect(await SecretVault.open(sealed), isNull);
    });

    test('pepper-only fallback round-trips and is sticky', () async {
      SecretVault.debugReset(deviceIdOverride: null);
      final sealed = await SecretVault.seal('no-device-id');
      expect(await SecretVault.open(sealed), 'no-device-id');
      // An id appearing on a LATER launch must not flip the key — this
      // install committed to pepper-only and stays readable forever.
      SecretVault.debugReset(deviceIdOverride: 'test-device-1');
      expect(await SecretVault.open(sealed), 'no-device-id');
      // A FRESH install that resolves an id derives a different key.
      SharedPreferences.setMockInitialValues({});
      SecretVault.debugReset(deviceIdOverride: 'test-device-1');
      expect(await SecretVault.open(sealed), isNull);
    });

    test('id-committed install refuses the fallback key on lookup failure',
        () async {
      SecretVault.debugReset(deviceIdOverride: 'dev-1');
      final sealed = await SecretVault.seal('bound');
      // Same install, transient device-info failure on a later launch: the
      // vault must NOT quietly derive the pepper key — reads act signed-out
      // and writes fail loudly instead of sealing under a key tomorrow's
      // launch can't reproduce.
      SecretVault.debugReset(deviceIdOverride: null);
      expect(await SecretVault.open(sealed), isNull);
      expect(SecretVault.seal('x'), throwsStateError);
      // Identity back → everything is still readable; the key never flipped.
      SecretVault.debugReset(deviceIdOverride: 'dev-1');
      expect(await SecretVault.open(sealed), 'bound');
    });
  });

  group('prefs helpers', () {
    test('getString lazily seals legacy plaintext', () async {
      SharedPreferences.setMockInitialValues(
          {'real_debrid_api_key': 'legacyKey40chars'});
      final prefs = await SharedPreferences.getInstance();
      expect(await SecretVault.getString(prefs, 'real_debrid_api_key'),
          'legacyKey40chars');
      final stored = prefs.getString('real_debrid_api_key')!;
      expect(stored, startsWith(SecretVault.prefix));
      expect(await SecretVault.open(stored), 'legacyKey40chars');
    });

    test('lazy migration loses a race to a concurrent write', () async {
      SharedPreferences.setMockInitialValues({'k': 'legacy-old'});
      final prefs = await SharedPreferences.getInstance();
      // Interleave: start the migrating read, then a token refresh writes a
      // NEW sealed value before the migration's write-back lands. The stale
      // migration must not resurrect the old credential.
      final migratingRead = SecretVault.getString(prefs, 'k');
      await SecretVault.setString(prefs, 'k', 'fresh-token');
      expect(await migratingRead, 'legacy-old');
      expect(await SecretVault.getString(prefs, 'k'), 'fresh-token');
    });

    test('setString stores sealed, getString returns plaintext', () async {
      final prefs = await SharedPreferences.getInstance();
      await SecretVault.setString(prefs, 'k', 'v');
      expect(prefs.getString('k'), startsWith(SecretVault.prefix));
      expect(await SecretVault.getString(prefs, 'k'), 'v');
    });

    test('missing key is null', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await SecretVault.getString(prefs, 'absent'), isNull);
    });

    test('getStringList drops undecryptable elements from the READ only',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final good = await SecretVault.seal('{"a":1}');
      await prefs.setStringList('list', [good, 'enc1:broken', 'legacy']);
      final out = await SecretVault.getStringList(prefs, 'list');
      expect(out, ['{"a":1}', 'legacy']);
      // A lossy read must NOT trigger the lazy migration rewrite — that
      // would turn a transient decrypt failure into permanent deletion.
      expect(prefs.getStringList('list'), hasLength(3));
    });

    test('getStringList migrates legacy elements off a clean read', () async {
      final prefs = await SharedPreferences.getInstance();
      final good = await SecretVault.seal('{"a":1}');
      await prefs.setStringList('list', [good, 'legacy']);
      expect(
          await SecretVault.getStringList(prefs, 'list'), ['{"a":1}', 'legacy']);
      final stored = prefs.getStringList('list')!;
      expect(stored, hasLength(2));
      expect(stored.every((e) => e.startsWith(SecretVault.prefix)), isTrue);
    });

    test('setStringList seals every element', () async {
      final prefs = await SharedPreferences.getInstance();
      await SecretVault.setStringList(prefs, 'list', ['x', 'y']);
      expect(
          prefs
              .getStringList('list')!
              .every((e) => e.startsWith(SecretVault.prefix)),
          isTrue);
      expect(await SecretVault.getStringList(prefs, 'list'), ['x', 'y']);
    });
  });

  group('field helpers', () {
    test('sealFields/openFields touch only named string fields', () async {
      final sealed = await SecretVault.sealFields({
        'url': 'http://host/get.php?username=u&password=p',
        'password': 'p',
        'name': 'My playlist',
        'count': 3,
        'epgUrl': null,
      }, const [
        'url',
        'password',
        'epgUrl'
      ]);
      expect(sealed['url'], startsWith(SecretVault.prefix));
      expect(sealed['password'], startsWith(SecretVault.prefix));
      expect(sealed['name'], 'My playlist');
      expect(sealed['count'], 3);
      expect(sealed['epgUrl'], isNull);

      final opened =
          await SecretVault.openFields(sealed, const ['url', 'password']);
      expect(opened.wasLegacy, isFalse);
      expect(opened.map['url'], 'http://host/get.php?username=u&password=p');
      expect(opened.map['password'], 'p');
    });

    test('openFields reports legacy plaintext and nulls failed fields',
        () async {
      final r = await SecretVault.openFields({
        'url': 'plain-url',
        'password': 'enc1:garbage',
      }, const [
        'url',
        'password'
      ]);
      expect(r.wasLegacy, isTrue);
      expect(r.map['url'], 'plain-url');
      expect(r.map['password'], isNull);
    });
  });
}
