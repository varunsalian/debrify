import 'package:debrify/services/remote_control/remote_network_addresses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'LAN addresses precede virtual interfaces regardless of enumeration order',
    () {
      final addresses = RemoteNetworkAddress.ordered(const [
        RemoteNetworkAddress('10.0.0.1', 'vEthernet (Virtual Switch)'),
        RemoteNetworkAddress('192.168.4.9', 'en0'),
        RemoteNetworkAddress('100.64.0.1', 'utun4'),
        RemoteNetworkAddress('192.168.4.9', 'en0'),
      ]);
      expect(addresses.first.address, '192.168.4.9');
      expect(addresses.map((a) => a.address).toSet().length, 3);
      expect(addresses.last.address, '100.64.0.1');
    },
  );
  test('only RFC1918 172.16 through 172.31 addresses are private', () {
    for (final address in ['172.16.0.1', '172.31.255.254']) {
      expect(RemoteNetworkAddress(address, 'en0').isPrivate, isTrue);
    }
    for (final address in ['172.15.0.1', '172.32.0.1', '172.100.0.1']) {
      expect(RemoteNetworkAddress(address, 'en0').isPrivate, isFalse);
    }
  });
}
