// The production [SportsFetch] adapter over package:http.
//
// Data layer: transport only — no parsing and no caching. The 15 s ceiling
// and the plain-text body contract are what [SportsFeedClient] expects.
import 'package:http/http.dart' as http;

import 'sports_feed_client.dart';

/// GETs [uri] expecting a JSON body.
///
/// Non-200 responses become [SportsFeedException]; transport errors (timeouts,
/// socket failures) propagate so the feed client can apply its stale fallback.
Future<String> httpSportsFetch(Uri uri) async {
  final response = await http
      .get(uri, headers: const {'Accept': 'application/json'})
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw SportsFeedException(uri, 'HTTP ${response.statusCode}');
  }
  return response.body;
}
