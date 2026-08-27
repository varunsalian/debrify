import 'dart:convert';

import 'package:crypto/crypto.dart';

/// How this app identifies itself to PikPak.
///
/// PikPak fingerprints its own web client and refuses requests that do not
/// look like it, so every call has to carry the same identity. That was being
/// rebuilt by hand in five places — the captcha request, the signin, both
/// refresh shapes, and every authenticated call — and they had drifted:
/// `X-Client-Version` was on two of the five, missing from every API call.
///
/// One value, built once, so a header can only be wrong everywhere or nowhere.
class PikPakClientIdentity {
  /// Matches a desktop Firefox, as rclone does. PikPak treats an unfamiliar
  /// agent as an unfamiliar client.
  final String userAgent;

  final String clientId;
  final String clientSecret;
  final String clientVersion;
  final String packageName;

  /// The salt chain PikPak's web client folds into its captcha signature.
  ///
  /// Reverse-engineered constants, meaningless outside PikPak and unusable by
  /// anything else — which is exactly why they belong here rather than in
  /// anything shared. They live with the rest of the fingerprint because that
  /// is what they are: [captchaSign] hashes the same clientId, clientVersion
  /// and packageName through them.
  final List<String> captchaSalts;

  const PikPakClientIdentity({
    required this.userAgent,
    required this.clientId,
    required this.clientSecret,
    required this.clientVersion,
    required this.packageName,
    required this.captchaSalts,
  });

  /// The `captcha_sign` PikPak expects for a request from [deviceId] at
  /// [timestamp]: the client's identity concatenated, then iteratively MD5'd
  /// through [captchaSalts].
  String captchaSign(String deviceId, String timestamp) {
    var value = clientId + clientVersion + packageName + deviceId + timestamp;
    for (final salt in captchaSalts) {
      value = md5.convert(utf8.encode(value + salt)).toString();
    }
    return '1.$value';
  }

  /// The identity as PikPak's captcha endpoint wants it — a body payload
  /// rather than headers, and the third place the same fingerprint appears.
  ///
  /// [captchaSign] and `timestamp` must be computed from the *same* instant or
  /// PikPak refuses the request, so this produces both together rather than
  /// leaving the caller to pair them. Pass [timestamp] to make it repeatable.
  ///
  /// PikPak wants [username] on a signin and [userId] on everything else; give
  /// it whichever the action calls for.
  Map<String, String> captchaMeta({
    required String deviceId,
    String? username,
    String? userId,
    String? timestamp,
  }) {
    final at = timestamp ?? DateTime.now().millisecondsSinceEpoch.toString();
    return {
      'captcha_sign': captchaSign(deviceId, at),
      'client_id': clientId,
      'client_version': clientVersion,
      'device_id': deviceId,
      'package_name': packageName,
      'timestamp': at,
      if (username != null && username.isNotEmpty) 'username': username,
      if ((username == null || username.isEmpty) &&
          userId != null &&
          userId.isNotEmpty)
        'user_id': userId,
    };
  }

  /// The identity every PikPak request carries, plus whatever of the
  /// per-request pieces the caller has.
  ///
  /// Lower-cased names: HTTP headers are case-insensitive, and normalising
  /// here means a caller's override replaces rather than duplicates.
  Map<String, String> headers({
    String? deviceId,
    String? captchaToken,
    String? accessToken,
  }) => {
    'user-agent': userAgent,
    'x-client-id': clientId,
    'x-client-version': clientVersion,
    if (deviceId != null && deviceId.isNotEmpty) 'x-device-id': deviceId,
    if (captchaToken != null && captchaToken.isNotEmpty)
      'x-captcha-token': captchaToken,
    if (accessToken != null && accessToken.isNotEmpty)
      'authorization': 'Bearer $accessToken',
  };
}
