import 'dart:convert';

import 'package:debrify/features/sources/data/deovr_json_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'uploads the unchanged JSON request and returns the hosted location',
    () async {
      const payload = {
        'title': 'VR title',
        'screenType': 'dome',
        'stereoMode': 'sbs',
      };
      var requests = 0;
      final result = await http.runWithClient(
        () => uploadDeoVrJson(payload),
        () => MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url, Uri.parse('https://jsonblob.com/api/jsonBlob'));
          expect(
            request.headers['content-type'],
            startsWith('application/json'),
          );
          expect(request.body, jsonEncode(payload));
          return http.Response(
            '',
            201,
            headers: {'location': '/api/jsonBlob/123'},
          );
        }),
      );
      expect(requests, 1);
      expect(result, 'https://jsonblob.com/api/jsonBlob/123');
    },
  );

  test(
    'rejects a non-created response with the original status error',
    () async {
      await expectLater(
        http.runWithClient(
          () => uploadDeoVrJson(const {}),
          () => MockClient((_) async => http.Response('', 503)),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            'Exception: Failed to upload JSON: 503',
          ),
        ),
      );
    },
  );

  test('rejects a created response without its location header', () async {
    await expectLater(
      http.runWithClient(
        () => uploadDeoVrJson(const {}),
        () => MockClient((_) async => http.Response('', 201)),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          'Exception: No location header in response',
        ),
      ),
    );
  });
}
