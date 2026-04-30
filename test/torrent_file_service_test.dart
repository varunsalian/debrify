import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/torrent_file_service.dart';

void main() {
  group('TorrentFileService', () {
    test('builds magnet from torrent bytes', () {
      final info =
          'd'
          '6:lengthi12345e'
          '${_bstr('name')}${_bstr('Example Movie')}'
          '${_bstr('piece length')}i16384e'
          '${_bstr('pieces')}${_bstr('abcdefghijklmnopqrst')}'
          'e';
      final torrent =
          'd'
          '${_bstr('announce')}${_bstr('https://tracker.example/announce')}'
          '${_bstr('announce-list')}'
          'll${_bstr('https://tracker.example/announce')}e'
          'l${_bstr('udp://tracker.example:80/announce')}e'
          'e'
          '${_bstr('info')}$info'
          'e';
      final expectedHash = sha1.convert(utf8.encode(info)).toString();

      final magnet = TorrentFileService.magnetFromTorrentBytes(
        Uint8List.fromList(utf8.encode(torrent)),
      );

      expect(magnet, startsWith('magnet:?xt=urn:btih:$expectedHash'));
      expect(magnet, contains('dn=Example%20Movie'));
      expect(magnet, contains('tr=https%3A%2F%2Ftracker.example%2Fannounce'));
      expect(
        magnet,
        contains('tr=udp%3A%2F%2Ftracker.example%3A80%2Fannounce'),
      );
    });
  });
}

String _bstr(String value) => '${utf8.encode(value).length}:$value';
