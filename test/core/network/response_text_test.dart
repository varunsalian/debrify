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

  test('keeps the Latin-1 reading for bodies that are not UTF-8', () {
    // An engine site serving ISO-8859-1 without a charset read correctly
    // before; strict UTF-8 must not turn its accents into U+FFFD.
    expect(
      responseText(response(latin1.encode('Amélie'), 'application/rss+xml')),
      'Amélie',
    );
  });
}
