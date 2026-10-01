import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage_service.dart';

void resetStorageProfileCaches() {
  PlayerSettingsStorage.resetProfileCaches();
  StorageService.resetProfileCaches();
}
