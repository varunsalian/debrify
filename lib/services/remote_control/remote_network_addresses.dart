import 'dart:io';

class RemoteNetworkAddress {
  const RemoteNetworkAddress(this.address, this.interfaceName);
  final String address;
  final String interfaceName;

  bool get isPrivate {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((n) => n == null)) return false;
    return parts[0] == 10 ||
        (parts[0] == 192 && parts[1] == 168) ||
        (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
  }

  bool get isVirtual => RegExp(
    r'^(utun|tun|tap|tailscale|docker|veth|virbr|vmnet|vbox|bridge)|vpn|virtual|hyper-v',
    caseSensitive: false,
  ).hasMatch(interfaceName);

  int get priority => (isVirtual ? 2 : 0) + (isPrivate ? 0 : 1);

  static List<RemoteNetworkAddress> ordered(
    Iterable<RemoteNetworkAddress> values,
  ) {
    final result = {
      for (final value in values) value.address: value,
    }.values.toList();
    result.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      return priority != 0 ? priority : a.address.compareTo(b.address);
    });
    return result;
  }

  static Future<List<RemoteNetworkAddress>> list() async => ordered([
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    ))
      for (final address in interface.addresses)
        if (!address.isLoopback)
          RemoteNetworkAddress(address.address, interface.name),
  ]);
}
