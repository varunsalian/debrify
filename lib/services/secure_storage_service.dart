import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  
  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: 'real_debrid_api_key', value: apiKey);
  }
  
  static Future<String?> getApiKey() async {
    return await _storage.read(key: 'real_debrid_api_key');
  }
  
  static Future<void> deleteApiKey() async {
    await _storage.delete(key: 'real_debrid_api_key');
  }
}
