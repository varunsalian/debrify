import 'dart:convert';

import 'package:debrify/core/network/response_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const title = 'Матрица — Amélie';

  http.Response response(List<int> bytes, String? contentType) =>
      http.Response.bytes(bytes, 200, headers: {'content-type': ?contentType});

  test('reads UTF-8 when no charset is sent', () {
    for (final type in [
      'application/rss+xml',
      'text/xml',
      'text/plain',
      null,
    ]) {
      expect(
        responseText(response(utf8.encode(title), type)),
        title,
        reason: '$type',
      );
    }
  });

  test('honours a charset the server names', () {
    expect(
      responseText(
        response(latin1.encode('Amélie'), 'text/xml; charset=ISO-8859-1'),
      ),
      'Amélie',
    );
  });

  test('does not throw on bytes that are not UTF-8', () {
    expect(responseText(response([0x41, 0xff, 0x42], 'text/xml')), 'A�B');
  });
}
