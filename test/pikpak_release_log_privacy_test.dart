import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PikPak logs never interpolate authentication material', () {
    final source = File(
      'lib/features/pikpak/data/api_service.dart',
    ).readAsStringSync();
    final logCalls = RegExp(
      r'(?:print|debugPrint)\s*\(([\s\S]*?)\);',
    ).allMatches(source);

    const forbiddenExpressions = <String>[
      r'$responseBody',
      r'${response.body}',
      r'$email',
      r'$deviceId',
      r'$captchaSign',
      r'$errorDesc',
      r'$_accessToken',
      r'$_refreshToken',
      r'$password',
      r'$captchaToken',
    ];

    for (final call in logCalls) {
      final body = call.group(1)!;
      for (final expression in forbiddenExpressions) {
        expect(
          body,
          isNot(contains(expression)),
          reason: 'Authentication material found in log call: $body',
        );
      }
    }
  });
}
