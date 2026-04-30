import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class TorrentFileService {
  const TorrentFileService._();

  static Future<String> magnetFromTorrentUrl(
    String torrentUrl, {
    String? fallbackName,
  }) async {
    final uri = Uri.tryParse(torrentUrl.trim());
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('Invalid torrent URL');
    }

    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Torrent download failed: HTTP ${response.statusCode}');
    }

    return magnetFromTorrentBytes(
      response.bodyBytes,
      fallbackName: fallbackName,
    );
  }

  static String magnetFromTorrentBytes(
    Uint8List bytes, {
    String? fallbackName,
  }) {
    final parser = _BencodeParser(bytes);
    final root = parser.parse();
    if (root is! _BencodeDictionary) {
      throw const FormatException('Torrent file root is not a dictionary');
    }

    final info = root.value['info'];
    if (info is! _BencodeDictionary) {
      throw const FormatException('Torrent file is missing info dictionary');
    }

    final hash = sha1.convert(bytes.sublist(info.start, info.end)).toString();
    final name =
        _stringValue(info.value['name.utf-8']) ??
        _stringValue(info.value['name']) ??
        fallbackName?.trim();
    final trackers = _trackers(root.value);

    final params = <String>[
      'xt=urn:btih:$hash',
      if (name != null && name.isNotEmpty) 'dn=${Uri.encodeComponent(name)}',
      ...trackers.map((tracker) => 'tr=${Uri.encodeComponent(tracker)}'),
    ];

    return 'magnet:?${params.join('&')}';
  }

  static String? _stringValue(Object? value) {
    if (value is Uint8List) return utf8.decode(value, allowMalformed: true);
    if (value is String) return value;
    return null;
  }

  static List<String> _trackers(Map<String, Object?> root) {
    final trackers = <String>{};
    final announce = _stringValue(root['announce']);
    if (announce != null && announce.isNotEmpty) trackers.add(announce);

    final announceList = root['announce-list'];
    if (announceList is List<Object?>) {
      for (final tier in announceList) {
        if (tier is List<Object?>) {
          for (final tracker in tier) {
            final value = _stringValue(tracker);
            if (value != null && value.isNotEmpty) trackers.add(value);
          }
        } else {
          final value = _stringValue(tier);
          if (value != null && value.isNotEmpty) trackers.add(value);
        }
      }
    }

    return trackers.toList(growable: false);
  }
}

class _BencodeDictionary {
  const _BencodeDictionary(this.value, this.start, this.end);

  final Map<String, Object?> value;
  final int start;
  final int end;
}

class _BencodeParser {
  _BencodeParser(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  Object? parse() {
    final value = _parseValue();
    if (_offset != _bytes.length) {
      throw const FormatException('Unexpected trailing torrent data');
    }
    return value;
  }

  Object? _parseValue() {
    _ensureAvailable();
    final byte = _bytes[_offset];

    if (byte == 0x64) return _parseDictionary(); // d
    if (byte == 0x6c) return _parseList(); // l
    if (byte == 0x69) return _parseInteger(); // i
    if (_isDigit(byte)) return _parseBytes();

    throw FormatException('Invalid bencode token at $_offset');
  }

  _BencodeDictionary _parseDictionary() {
    final start = _offset;
    _offset++;
    final map = <String, Object?>{};

    while (true) {
      _ensureAvailable();
      if (_bytes[_offset] == 0x65) {
        _offset++;
        return _BencodeDictionary(map, start, _offset);
      }

      final keyBytes = _parseBytes();
      final key = utf8.decode(keyBytes, allowMalformed: true);
      map[key] = _parseValue();
    }
  }

  List<Object?> _parseList() {
    _offset++;
    final values = <Object?>[];

    while (true) {
      _ensureAvailable();
      if (_bytes[_offset] == 0x65) {
        _offset++;
        return values;
      }
      values.add(_parseValue());
    }
  }

  int _parseInteger() {
    _offset++;
    final start = _offset;
    while (true) {
      _ensureAvailable();
      if (_bytes[_offset] == 0x65) {
        final text = ascii.decode(_bytes.sublist(start, _offset));
        _offset++;
        return int.parse(text);
      }
      _offset++;
    }
  }

  Uint8List _parseBytes() {
    final lengthStart = _offset;
    while (true) {
      _ensureAvailable();
      if (_bytes[_offset] == 0x3a) break; // :
      if (!_isDigit(_bytes[_offset])) {
        throw FormatException('Invalid string length at $_offset');
      }
      _offset++;
    }

    final length = int.parse(
      ascii.decode(_bytes.sublist(lengthStart, _offset)),
    );
    _offset++;
    final valueStart = _offset;
    final valueEnd = valueStart + length;
    if (valueEnd > _bytes.length) {
      throw const FormatException('Torrent string exceeds file length');
    }
    _offset = valueEnd;
    return Uint8List.sublistView(_bytes, valueStart, valueEnd);
  }

  void _ensureAvailable() {
    if (_offset >= _bytes.length) {
      throw const FormatException('Unexpected end of torrent file');
    }
  }

  bool _isDigit(int byte) => byte >= 0x30 && byte <= 0x39;
}
