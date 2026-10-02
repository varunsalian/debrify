import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/text_brightness_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/widgets/launch/launch_ident.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice04 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice4() {
    return [
      // Appearance — one contiguous block so the category groups directly
      // after Home & Display (results group by FIRST appearance). The old
      // category strings ride along as keywords: the category text is part
      // of the match haystack, and matching splits on whitespace only, so
      // dropping 'Home & Display'/'Live TV & DVR' from these entries would
      // break exact old-category searches.
      // Ungated — every platform has text. Lands on the picker.
      nav(
        SettingsRows.textBrightness,
        'Appearance',
        deps.openTextBrightnessPage,
        subtitle: textBrightnessLabel(summaries.textBrightness),
        keywords: [
          'text',
          'font',
          'color',
          'colour',
          'grey',
          'gray',
          'white',
          'dim',
          'dimmer',
          'brightness',
          'bright',
          'oled',
          'amoled',
          'contrast',
          'glare',
          'display',
          ...labels(TextBrightness.values.map((choice) => choice.label)),
        ],
      ),
      // Ungated — every platform plays the splash. Lands on the picker.
      nav(
        SettingsRows.launchAnimation,
        'Appearance',
        deps.openLaunchAnimationPage,
        subtitle: launchIdentLabel(summaries.launchAnimation),
        keywords: [
          'launch',
          'splash',
          'intro',
          'animation',
          'boot',
          'start',
          'startup',
          'logo',
          'ident',
          'opening',
          'neon',
          'chrome',
          'marquee',
          'prism',
          'monogram',
          'match app theme',
          'ident colour',
          'ident color',
          ...labels(kLaunchIdents.map((ident) => ident.label)),
        ],
      ),
      // Android TV only — the size factor is applied natively in
      // MainActivity, so the row would be inert anywhere else.
      if (summaries.isAndroidTv)
        nav(
          SettingsRows.tvScreenSize,
          'Appearance',
          deps.openTvScreenSize,
          subtitle: tvUiScaleLabel(summaries.tvUiScalePercent),
          keywords: [
            'zoom',
            'zoomed in',
            'scale',
            'ui size',
            'text size',
            'font size',
            'bigger',
            'smaller',
            'density',
            'dpi',
            'resolution',
            'compact',
            'fit more',
            'display',
            'home & display',
            ...labels(kTvUiScaleChoices.map((choice) => choice.label)),
          ],
        ),
      // Android TV only — the render scale is applied natively in
      // MainActivity, so the row would be inert anywhere else. Keyworded for
      // the SYMPTOM: nobody searches "render scale", they search "stutter".
      if (summaries.isAndroidTv)
        nav(
          SettingsRows.tvRenderQuality,
          'Appearance',
          deps.openTvRenderQuality,
          subtitle: tvRenderQualityLabel(summaries.tvRenderQuality),
          keywords: [
            'stutter',
            'stuttering',
            'lag',
            'laggy',
            'jank',
            'janky',
            'choppy',
            'slow',
            'smooth',
            'smoothness',
            'performance',
            'fps',
            'frame rate',
            'speed',
            'scrolling',
            'resolution',
            'render',
            'rendering',
            '720p',
            '1080p',
            'sharp',
            'sharpness',
            'blurry',
            'soft',
            'quality',
            'gpu',
            'graphics',
            'display',
            'home & display',
            ...labels(kTvRenderQualityChoices.map((choice) => choice.label)),
          ],
        ),
    ];
  }
}
