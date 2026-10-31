// Matching a channel's other versions by name, with the names a real
// provider uses (superscript quality tags, region prefixes, 4K sections).
import 'package:debrify/features/iptv_multiview/models/channel_versions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quality reads plain and superscript tags', () {
    expect(channelQuality('4K: ELEVEN SPORTS 1 ᵁᴴᴰ ³⁸⁴⁰ᴾ'), 3);
    expect(channelQuality('PL: ELEVEN SPORTS 1 4K/UHD'), 3);
    expect(channelQuality('PL: ELEVEN SPORTS 1 4K+'), 3);
    expect(channelQuality('UK: SKY SPORTS F1 FHD'), 2);
    expect(channelQuality('PL: ELEVEN SPORTS 1 ᴿᴬᵂ'), 2, reason: 'raw feed');
    expect(channelQuality('PL: ELEVEN SPORTS 1 ᴴᴰ ◉'), 1);
    expect(channelQuality('Eleven Sports 1'), 1, reason: 'no tag');
    expect(channelQuality('BBC One SD'), 0);
  });

  test('identity drops region and quality, keeps the channel', () {
    expect(
      channelIdentity('4K: ELEVEN SPORTS 1 ᵁᴴᴰ ³⁸⁴⁰ᴾ'),
      (region: '', base: 'eleven sports 1'),
      reason: 'a "4K:" section is not a region',
    );
    expect(channelIdentity('PL: ELEVEN SPORTS 1 ᴴᴰ ◉'), (
      region: 'pl',
      base: 'eleven sports 1',
    ));
    expect(
      channelIdentity('PL VIP: ELEVEN SPORTS 1 RAW 4K 3840P').base,
      'eleven sports 1',
    );
    expect(channelIdentity('Eleven Sports 1').base, 'eleven sports 1');
    expect(channelIdentity('PL: ELEVEN SPORTS 10 ᴴᴰ').base, 'eleven sports 10');
  });

  test('a 4K channel falls back to lower quality first, same region first', () {
    final candidates = [
      'PL: ELEVEN SPORTS 1 ᵁᴴᴰ',
      'PL: ELEVEN SPORTS 1 ᴴᴰ',
      'PL: ELEVEN SPORTS 1 ᴿᴬᵂ',
      'DE: ELEVEN SPORTS 1 HD',
      'PL: ELEVEN SPORTS 10 ᴴᴰ',
      'PL: CANAL+ SPORT HD',
      '4K: ELEVEN SPORTS 1 ᵁᴴᴰ ³⁸⁴⁰ᴾ',
    ];
    final ordered = orderChannelVersions<String>(
      name: '4K: ELEVEN SPORTS 1 ᵁᴴᴰ ³⁸⁴⁰ᴾ',
      url: '4K: ELEVEN SPORTS 1 ᵁᴴᴰ ³⁸⁴⁰ᴾ',
      candidates: candidates,
      nameOf: (c) => c,
      urlOf: (c) => c,
    );
    expect(ordered.take(2), [
      'PL: ELEVEN SPORTS 1 ᴿᴬᵂ', // FHD-class before HD
      'PL: ELEVEN SPORTS 1 ᴴᴰ',
    ]);
    expect(ordered, contains('DE: ELEVEN SPORTS 1 HD'));
    expect(ordered.last, 'PL: ELEVEN SPORTS 1 ᵁᴴᴰ', reason: 'same 4K, last');
    expect(ordered, isNot(contains('PL: ELEVEN SPORTS 10 ᴴᴰ')));
    expect(ordered, isNot(contains('PL: CANAL+ SPORT HD')));
    expect(ordered, isNot(contains('4K: ELEVEN SPORTS 1 ᵁᴴᴰ ³⁸⁴⁰ᴾ')));
  });

  test('never offers a sharper version than the original', () {
    final ordered = orderChannelVersions<String>(
      name: 'UK: SKY SPORTS F1 HD',
      url: 'a',
      candidates: [
        'UK: SKY SPORTS F1 4K',
        'UK: SKY SPORTS F1 SD',
        'DE: SKY SPORTS F1 HD',
      ],
      nameOf: (c) => c,
      urlOf: (c) => c,
    );
    // Not 4K: its stream failed, so another copy at the same quality first.
    expect(ordered, ['DE: SKY SPORTS F1 HD', 'UK: SKY SPORTS F1 SD']);
  });
}
