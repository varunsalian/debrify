import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/debrid_download.dart';

class DebridService {
  static const String _baseUrl = 'https://api.real-debrid.com/rest/1.0';

  static Future<List<DebridDownload>> getDownloads(String apiKey) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/downloads?auth_token=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => DebridDownload.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key. Please check your Real Debrid API key.');
      } else {
        throw Exception('Failed to load downloads. Please try again.');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error. Please check your connection.');
    }
  }
} 