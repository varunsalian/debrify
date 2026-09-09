import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:debrify/utils/canonical_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'incremental canonical hash preserves escaping, ordering and Unicode',
    () {
      for (final count in [0, 1, 16382, 16383, 16384, 16385, 65536]) {
        final value = {
          'z': [true, false, null, -0.0, 1.2e33, 1, -55],
          'a': '${'a' * count}😀\n\t"\\\u0000中',
          'nested': {
            'z': [1, 2],
            'a': {'B': 'b', 'A': 'a'},
          },
        };
        final encoded = utf8.encode(encodeCanonicalJson(value));
        final measured = measureCanonicalJson(value);
        expect(measured.sha256, sha256.convert(encoded).toString());
        expect(measured.bytes, encoded.length);
        expect(canonicalJsonFragments(value).join(), utf8.decode(encoded));
      }
    },
  );
}
