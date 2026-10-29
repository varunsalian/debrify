import 'package:flutter_test/flutter_test.dart';

import '../../../../support/lib_source.dart';

void main() {
  test('42 resources dispose in order before super', () {
    final dispose = libMember(
      'lib/screens/settings/external_player_settings_page.dart',
      'dispose',
      owner: '_ExternalPlayerSettingsPageState',
    );
    final disposals = [
      for (final match in RegExp(
        r'(\w+)\s*\.\s*dispose\s*\(',
      ).allMatches(dispose))
        match[1]!,
    ];
    expect(disposals, const [
      'commandController',
      'commandFocusNode',
      'iosSchemeController',
      'iosSchemeFocusNode',
      'linuxCommandController',
      'linuxCommandFocusNode',
      'windowsCommandController',
      'windowsCommandFocusNode',
      'firstModeFocusNode',
      'contentFocusNode',
      'screenTypeFocusNode',
      'stereoModeFocusNode',
      'autoDetectFocusNode',
      'showDialogFocusNode',
      'aspectFocusNode',
      'defaultAudioLangFocusNode',
      'defaultSubtitleLangFocusNode',
      'systemAudioEffectsFocusNode',
      'tvosForceSwDecodeFocusNode',
      'audioPassthroughFocusNode',
      'appleMultichannelFocusNode',
      'tvosForceStereoFocusNode',
      'tvosLegacyAudioFocusNode',
      'androidVideoRendererFocusNode',
      'contentDisplayMatchFocusNode',
      'iptvDecoderFocusNode',
      'startPortraitFocusNode',
      'subtitleOnlyForeignAudioFocusNode',
      'subtitleForcedOnlyFocusNode',
      'subtitleAutoSyncFocusNode',
      'movieCompletionThresholdFocusNode',
      'episodeCompletionThresholdFocusNode',
      'skipSegmentsEnabledFocusNode',
      'skipSegmentProviderFocusNode',
      'subtitleSizeFocusNode',
      'subtitleStyleFocusNode',
      'subtitleColorFocusNode',
      'subtitleBgFocusNode',
      'subtitleFontFocusNode',
      'subtitleBoldFocusNode',
      'netPatienceFocusNode',
      'netBufferFocusNode',
      'super',
    ]);
    expect(disposals, hasLength(43));
  });
}
