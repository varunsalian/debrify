import 'package:flutter/material.dart';

class PlaybackSubtitleRowsState {
  final FocusNode defaultSubtitleLangFocusNode = FocusNode();

  final FocusNode subtitleOnlyForeignAudioFocusNode = FocusNode();

  final FocusNode subtitleForcedOnlyFocusNode = FocusNode();

  final FocusNode subtitleAutoSyncFocusNode = FocusNode();

  final FocusNode movieCompletionThresholdFocusNode = FocusNode();

  final FocusNode episodeCompletionThresholdFocusNode = FocusNode();

  final FocusNode skipSegmentsEnabledFocusNode = FocusNode();

  final FocusNode skipSegmentProviderFocusNode = FocusNode();

  final FocusNode subtitleSizeFocusNode = FocusNode();

  final FocusNode subtitleStyleFocusNode = FocusNode();

  final FocusNode subtitleColorFocusNode = FocusNode();

  final FocusNode subtitleBgFocusNode = FocusNode();

  final FocusNode subtitleFontFocusNode = FocusNode();

  final FocusNode subtitleBoldFocusNode = FocusNode();

  bool defaultSubtitleLangFocused = false;

  bool subtitleOnlyForeignAudioFocused = false;

  bool subtitleForcedOnlyFocused = false;

  bool subtitleAutoSyncFocused = false;

  bool movieCompletionThresholdFocused = false;

  bool episodeCompletionThresholdFocused = false;

  bool skipSegmentsEnabledFocused = false;

  bool skipSegmentProviderFocused = false;

  bool subtitleSizeFocused = false;

  bool subtitleStyleFocused = false;

  bool subtitleColorFocused = false;

  bool subtitleBgFocused = false;

  bool subtitleFontFocused = false;

  bool subtitleBoldFocused = false;
}
