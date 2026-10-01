import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/discover_storage.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/launch_ident_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/sidebar_storage.dart';
import 'package:debrify/services/storage/theme_storage.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/services/storage/ui_feedback_storage.dart';
import 'package:debrify/services/storage_service.dart';

void resetStorageProfileCaches() {
  TvDisplayStorage.resetProfileCaches();
  HomeAppearanceStorage.resetProfileCaches();
  DetailPageStorage.resetProfileCaches();
  ThemeStorage.resetProfileCaches();
  DiscoverStorage.resetProfileCaches();
  LaunchIdentStorage.resetProfileCaches();
  SidebarStorage.resetProfileCaches();
  PlayerSettingsStorage.resetProfileCaches();
  UiFeedbackStorage.resetProfileCaches();
  StorageService.resetProfileCaches();
}
