import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dropbox_auth_service.dart';

class DropboxService {
  static const String _baseUrl = 'https://api.dropboxapi.com/2';
  static const String _contentUrl = 'https://content.dropboxapi.com/2';

  /// Get current account information including email
  static Future<DropboxAccountResult> getCurrentAccount() async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxAccountResult(
          success: false,
          error: 'No access token available',
        );
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/users/get_current_account'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: 'null', // Dropbox API expects 'null' for empty request body
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DropboxAccountResult(
          success: true,
          accountId: data['account_id'],
          email: data['email'],
          displayName: data['name']['display_name'],
          country: data['country'],
        );
      } else {
        debugPrint('Failed to get account info: ${response.statusCode} - ${response.body}');
        return DropboxAccountResult(
          success: false,
          error: 'Failed to get account information: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox getCurrentAccount error: $e');
      return DropboxAccountResult(
        success: false,
        error: 'Failed to get account information: $e',
      );
    }
  }

  /// Create the /debrify folder in the app folder
  static Future<DropboxFolderResult> createDebrifyFolder() async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxFolderResult(
          success: false,
          error: 'No access token available',
        );
      }

      final requestBody = {
        'path': '/debrify',
        'autorename': false,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/files/create_folder_v2'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final metadata = data['metadata'];
        return DropboxFolderResult(
          success: true,
          folderId: metadata['id'],
          folderPath: metadata['path_display'],
          folderName: metadata['name'],
        );
      } else if (response.statusCode == 409) {
        // Folder already exists, get its metadata
        return await _getFolderMetadata('/debrify');
      } else {
        debugPrint('Failed to create folder: ${response.statusCode} - ${response.body}');
        return DropboxFolderResult(
          success: false,
          error: 'Failed to create folder: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox createDebrifyFolder error: $e');
      return DropboxFolderResult(
        success: false,
        error: 'Failed to create folder: $e',
      );
    }
  }

  /// Get metadata for an existing folder
  static Future<DropboxFolderResult> _getFolderMetadata(String path) async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxFolderResult(
          success: false,
          error: 'No access token available',
        );
      }

      final requestBody = {
        'path': path,
        'include_media_info': false,
        'include_deleted': false,
        'include_has_explicit_shared_members': false,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/files/get_metadata'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DropboxFolderResult(
          success: true,
          folderId: data['id'],
          folderPath: data['path_display'],
          folderName: data['name'],
        );
      } else {
        debugPrint('Failed to get folder metadata: ${response.statusCode} - ${response.body}');
        return DropboxFolderResult(
          success: false,
          error: 'Failed to get folder metadata: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox getFolderMetadata error: $e');
      return DropboxFolderResult(
        success: false,
        error: 'Failed to get folder metadata: $e',
      );
    }
  }

  /// Check if the /debrify folder exists
  static Future<bool> doesDebrifyFolderExist() async {
    try {
      final result = await _getFolderMetadata('/debrify');
      return result.success;
    } catch (e) {
      debugPrint('Error checking folder existence: $e');
      return false;
    }
  }

  /// List contents of the /debrify folder
  static Future<DropboxListResult> listDebrifyFolder() async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxListResult(
          success: false,
          error: 'No access token available',
        );
      }

      final requestBody = {
        'path': '/debrify',
        'recursive': false,
        'include_media_info': false,
        'include_deleted': false,
        'include_has_explicit_shared_members': false,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/files/list_folder'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final entries = data['entries'] as List;
        return DropboxListResult(
          success: true,
          entries: entries,
          hasMore: data['has_more'] ?? false,
          cursor: data['cursor'],
        );
      } else {
        debugPrint('Failed to list folder: ${response.statusCode} - ${response.body}');
        return DropboxListResult(
          success: false,
          error: 'Failed to list folder: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox listDebrifyFolder error: $e');
      return DropboxListResult(
        success: false,
        error: 'Failed to list folder: $e',
      );
    }
  }

  /// Upload string content to the /Apps/Debrify folder
  static Future<DropboxUploadResult> uploadStringContent(String content, String fileName) async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxUploadResult(
          success: false,
          error: 'No access token available',
        );
      }

      final contentBytes = utf8.encode(content);
      final dropboxPath = '/Apps/Debrify/$fileName';

      final request = http.Request('POST', Uri.parse('$_contentUrl/files/upload'));
      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Dropbox-API-Arg'] = json.encode({
        'path': dropboxPath,
        'mode': 'overwrite',
        'autorename': false,
        'mute': false,
      });
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = contentBytes;

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final data = json.decode(responseBody);
        return DropboxUploadResult(
          success: true,
          fileId: data['id'],
          filePath: data['path_display'],
          fileName: data['name'],
          size: data['size'],
        );
      } else {
        debugPrint('Failed to upload string content: ${streamedResponse.statusCode} - $responseBody');
        return DropboxUploadResult(
          success: false,
          error: 'Failed to upload string content: ${streamedResponse.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox uploadStringContent error: $e');
      return DropboxUploadResult(
        success: false,
        error: 'Failed to upload string content: $e',
      );
    }
  }

  /// Upload a file to the /debrify folder
  static Future<DropboxUploadResult> uploadFile(String localPath, String fileName) async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxUploadResult(
          success: false,
          error: 'No access token available',
        );
      }

      final file = File(localPath);
      if (!await file.exists()) {
        return DropboxUploadResult(
          success: false,
          error: 'Local file does not exist',
        );
      }

      final fileBytes = await file.readAsBytes();
      final dropboxPath = '/Apps/Debrify/$fileName';

      final request = http.Request('POST', Uri.parse('$_contentUrl/files/upload'));
      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Dropbox-API-Arg'] = json.encode({
        'path': dropboxPath,
        'mode': 'add',
        'autorename': true,
        'mute': false,
      });
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = fileBytes;

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final data = json.decode(responseBody);
        return DropboxUploadResult(
          success: true,
          fileId: data['id'],
          filePath: data['path_display'],
          fileName: data['name'],
          size: data['size'],
        );
      } else {
        debugPrint('Failed to upload file: ${streamedResponse.statusCode} - $responseBody');
        return DropboxUploadResult(
          success: false,
          error: 'Failed to upload file: ${streamedResponse.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox uploadFile error: $e');
      return DropboxUploadResult(
        success: false,
        error: 'Failed to upload file: $e',
      );
    }
  }

  /// Delete a file from the /debrify folder
  static Future<DropboxDeleteResult> deleteFile(String fileName) async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxDeleteResult(
          success: false,
          error: 'No access token available',
        );
      }

      final dropboxPath = '/Apps/Debrify/$fileName';
      final requestBody = {
        'path': dropboxPath,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/files/delete_v2'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        return DropboxDeleteResult(
          success: true,
          fileName: fileName,
        );
      } else {
        debugPrint('Failed to delete file: ${response.statusCode} - ${response.body}');
        return DropboxDeleteResult(
          success: false,
          error: 'Failed to delete file: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox deleteFile error: $e');
      return DropboxDeleteResult(
        success: false,
        error: 'Failed to delete file: $e',
      );
    }
  }

  /// Download a file from the /debrify folder
  static Future<DropboxDownloadResult> downloadFile(String fileName) async {
    try {
      final accessToken = await DropboxAuthService.getAccessToken();
      if (accessToken == null) {
        return DropboxDownloadResult(
          success: false,
          error: 'No access token available',
        );
      }

      final dropboxPath = '/Apps/Debrify/$fileName';
      debugPrint('🔍 Downloading file from path: $dropboxPath');

      final request = http.Request('POST', Uri.parse('$_contentUrl/files/download'));
      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Dropbox-API-Arg'] = json.encode({'path': dropboxPath});

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      debugPrint('🔍 Download response status: ${streamedResponse.statusCode}');
      debugPrint('🔍 Download response body: $responseBody');

      if (streamedResponse.statusCode == 200) {
        return DropboxDownloadResult(
          success: true,
          content: responseBody,
          fileName: fileName,
        );
      } else {
        debugPrint('Failed to download file: ${streamedResponse.statusCode} - $responseBody');
        return DropboxDownloadResult(
          success: false,
          error: 'Failed to download file: ${streamedResponse.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Dropbox downloadFile error: $e');
      return DropboxDownloadResult(
        success: false,
        error: 'Failed to download file: $e',
      );
    }
  }
}

/// Result class for Dropbox account operations
class DropboxAccountResult {
  final bool success;
  final String? accountId;
  final String? email;
  final String? displayName;
  final String? country;
  final String? error;

  DropboxAccountResult({
    required this.success,
    this.accountId,
    this.email,
    this.displayName,
    this.country,
    this.error,
  });
}

/// Result class for Dropbox folder operations
class DropboxFolderResult {
  final bool success;
  final String? folderId;
  final String? folderPath;
  final String? folderName;
  final String? error;

  DropboxFolderResult({
    required this.success,
    this.folderId,
    this.folderPath,
    this.folderName,
    this.error,
  });
}

/// Result class for Dropbox list operations
class DropboxListResult {
  final bool success;
  final List<dynamic>? entries;
  final bool hasMore;
  final String? cursor;
  final String? error;

  DropboxListResult({
    required this.success,
    this.entries,
    this.hasMore = false,
    this.cursor,
    this.error,
  });
}

/// Result class for Dropbox upload operations
class DropboxUploadResult {
  final bool success;
  final String? fileId;
  final String? filePath;
  final String? fileName;
  final int? size;
  final String? error;

  DropboxUploadResult({
    required this.success,
    this.fileId,
    this.filePath,
    this.fileName,
    this.size,
    this.error,
  });
}

/// Result class for Dropbox download operations
class DropboxDownloadResult {
  final bool success;
  final String? content;
  final String? fileName;
  final String? error;

  DropboxDownloadResult({
    required this.success,
    this.content,
    this.fileName,
    this.error,
  });
}

/// Result class for Dropbox delete operations
class DropboxDeleteResult {
  final bool success;
  final String? fileName;
  final String? error;

  DropboxDeleteResult({
    required this.success,
    this.fileName,
    this.error,
  });
}
