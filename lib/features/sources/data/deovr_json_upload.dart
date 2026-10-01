import 'dart:convert';

import 'package:http/http.dart' as http;

Future<String> uploadDeoVrJson(Map<String, dynamic> json) async {
  final response = await http.post(
    Uri.parse('https://jsonblob.com/api/jsonBlob'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(json),
  );
  if (response.statusCode != 201) {
    throw Exception('Failed to upload JSON: ${response.statusCode}');
  }
  final location = response.headers['location'];
  if (location == null) {
    throw Exception('No location header in response');
  }
  return 'https://jsonblob.com$location';
}
