import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/iptv_epg_service.dart';

void main() {
  group('stripFeedSuffix', () {
    test('strips an iptv-org feed suffix', () {
      expect(IptvEpgService.stripFeedSuffix('BBCOne.uk@SD'), 'BBCOne.uk');
      expect(IptvEpgService.stripFeedSuffix('CNN.us@HD'), 'CNN.us');
    });

    test('leaves ids without a suffix unchanged', () {
      expect(IptvEpgService.stripFeedSuffix('BBCOne.uk'), 'BBCOne.uk');
      expect(IptvEpgService.stripFeedSuffix('US1000005GY'), 'US1000005GY');
    });

    test('only the first @ splits — the rest stays with the feed', () {
      expect(IptvEpgService.stripFeedSuffix('Odd.id@SD@extra'), 'Odd.id');
    });

    test('a leading @ is not a suffix', () {
      expect(IptvEpgService.stripFeedSuffix('@weird'), '@weird');
    });
  });
}
