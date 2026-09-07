import 'dart:convert';

import 'package:http/http.dart' as http;

/// Older Trakt responses return the complete history without pagination
/// headers. Current responses explicitly describe their pages. Never probe an
/// unpaginated response: that downloads the same history again.
Future<List<dynamic>?> readTraktWatchedShowHistory(
  Future<http.Response?> Function(String path) get,
) async {
  final result = <dynamic>[];
  var page = 1;
  try {
    while (page <= 100) {
      final response = await get(
        '/sync/watched/shows?extended=noseasons&page=$page&limit=250',
      );
      if (response == null || response.statusCode != 200) return null;
      final rows = jsonDecode(response.body);
      if (rows is! List<dynamic>) return null;
      result.addAll(rows);

      final headers = response.headers;
      final paginated = headers.keys.any(
        (key) => key.startsWith('x-pagination-'),
      );
      if (!paginated) {
        // A later page losing its pagination contract is not a complete read.
        return page == 1 ? result : null;
      }
      int? header(String name) =>
          int.tryParse(headers[name]?.split(',').first.trim() ?? '');
      final count = header('x-pagination-page-count');
      final current = header('x-pagination-page');
      if (current != null && current != page) return null;
      if (count == null || count < 0) return null;
      if (count == 0) return page == 1 && rows.isEmpty ? result : null;
      if (count < page || (rows.isEmpty && page < count)) return null;
      if (page == count) return result;
      page++;
    }
  } catch (_) {
    return null;
  }
  return null;
}
