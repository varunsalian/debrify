import 'dart:convert';

import 'package:http/http.dart' as http;

/// The text of [response], read as UTF-8 unless the server names a charset.
///
/// Without a charset the http package falls back to Latin-1 for everything
/// but `application/json`, yet XML and JSON are UTF-8 by default and that is
/// what indexers and search sites send. Prowlarr's Torznab feed, for one, is
/// `application/rss+xml` with no charset, so Cyrillic and accented titles came
/// out garbled (#101). An explicit charset still wins.
String responseText(http.Response response) {
  final type = response.headers['content-type']?.toLowerCase() ?? '';
  if (type.contains('charset=')) return response.body;
  return utf8.decode(response.bodyBytes, allowMalformed: true);
}
