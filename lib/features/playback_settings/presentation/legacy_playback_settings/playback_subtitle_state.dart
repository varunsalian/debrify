import 'package:debrify/services/subtitle_font_service.dart';

class PlaybackSubtitleState {
  bool subtitleOnlyForeignAudio = false;

  bool subtitleForcedOnly = false;

  bool subtitleAutoSync = false; // Native players only, experimental opt-in

  String?
  defaultSubtitleLanguage; // null = no preference, 'off' = disabled, 'en'/'es'/etc = language

  String?
  defaultAudioLanguage; // null = no preference, 'en'/'es'/etc = language

  int subtitleSizeIndex = 2; // Medium

  int subtitleStyleIndex = 1; // Outline

  int subtitleColorIndex = 0; // White

  int subtitleBgIndex = 0; // None

  int subtitleFontIndex = 0; // Default

  bool subtitleBold = false; // normal weight

  List<SubtitleFont> allFonts =
      SubtitleFont.builtInOptions; // Built-in + custom fonts
}
