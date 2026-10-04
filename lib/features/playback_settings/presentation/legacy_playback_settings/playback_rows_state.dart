import 'package:flutter/material.dart';

class PlaybackRowsState {
  // Debrify Player FocusNodes for DPAD navigation
  final FocusNode aspectFocusNode = FocusNode();

  final FocusNode defaultAudioLangFocusNode = FocusNode();

  final FocusNode systemAudioEffectsFocusNode = FocusNode();

  final FocusNode tvosForceSwDecodeFocusNode = FocusNode();

  final FocusNode audioPassthroughFocusNode = FocusNode();

  final FocusNode appleMultichannelFocusNode = FocusNode();

  final FocusNode tvosForceStereoFocusNode = FocusNode();

  final FocusNode tvosLegacyAudioFocusNode = FocusNode();

  final FocusNode androidVideoRendererFocusNode = FocusNode();

  final FocusNode contentDisplayMatchFocusNode = FocusNode();

  final FocusNode iptvDecoderFocusNode = FocusNode();

  final FocusNode startPortraitFocusNode = FocusNode();

  final FocusNode netPatienceFocusNode = FocusNode();

  final FocusNode netBufferFocusNode = FocusNode();

  bool aspectFocused = false;

  bool defaultAudioLangFocused = false;

  bool systemAudioEffectsFocused = false;

  bool tvosForceSwDecodeFocused = false;

  bool audioPassthroughFocused = false;

  bool appleMultichannelFocused = false;

  bool tvosForceStereoFocused = false;

  bool tvosLegacyAudioFocused = false;

  bool androidVideoRendererFocused = false;

  bool contentDisplayMatchFocused = false;

  bool iptvDecoderFocused = false;

  bool startPortraitFocused = false;

  bool netPatienceFocused = false;

  bool netBufferFocused = false;
}
