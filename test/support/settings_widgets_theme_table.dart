import 'package:flutter/material.dart';

// Snapshot public resolved ThemeData, never the private builder's source or
// formulas. All combinations include pressed for styleFrom's overlay rules.
const settingsThemeStates = [
  WidgetState.selected,
  WidgetState.disabled,
  WidgetState.focused,
  WidgetState.hovered,
  WidgetState.pressed,
];

Object? themeValue(Object? value) => switch (value) {
  null => null,
  Color c => {
    'argb': c.toARGB32().toRadixString(16).padLeft(8, '0'),
    'components': [c.a, c.r, c.g, c.b],
    'space': c.colorSpace.name,
  },
  TextStyle s => {
    'inherit': s.inherit,
    'color': themeValue(s.color),
    'backgroundColor': themeValue(s.backgroundColor),
    'fontFamily': s.fontFamily,
    'fontFamilyFallback': s.fontFamilyFallback,
    'fontSize': s.fontSize,
    'fontWeight': s.fontWeight?.value,
    'fontStyle': s.fontStyle?.name,
    'letterSpacing': s.letterSpacing,
    'wordSpacing': s.wordSpacing,
    'height': s.height,
    'decoration': s.decoration?.toString(),
    'decorationColor': themeValue(s.decorationColor),
    'decorationStyle': s.decorationStyle?.name,
    'decorationThickness': s.decorationThickness,
  },
  BorderSide s => {
    'color': themeValue(s.color),
    'width': s.width,
    'style': s.style.name,
    'strokeAlign': s.strokeAlign,
  },
  RoundedRectangleBorder s => {
    'type': 'RoundedRectangleBorder',
    'side': themeValue(s.side),
    'radius': themeValue(s.borderRadius),
  },
  OutlineInputBorder s => {
    'type': 'OutlineInputBorder',
    'side': themeValue(s.borderSide),
    'radius': themeValue(s.borderRadius),
    'gapPadding': s.gapPadding,
  },
  BorderRadiusGeometry r => [
    for (final corner in [
      r.resolve(TextDirection.ltr).topLeft,
      r.resolve(TextDirection.ltr).topRight,
      r.resolve(TextDirection.ltr).bottomRight,
      r.resolve(TextDirection.ltr).bottomLeft,
    ])
      [corner.x, corner.y],
  ],
  EdgeInsetsGeometry e => [
    e.resolve(TextDirection.ltr).left,
    e.resolve(TextDirection.ltr).top,
    e.resolve(TextDirection.ltr).right,
    e.resolve(TextDirection.ltr).bottom,
  ],
  Size s => [themeValue(s.width), themeValue(s.height)],
  AlignmentGeometry a => [
    a.resolve(TextDirection.ltr).x,
    a.resolve(TextDirection.ltr).y,
  ],
  VisualDensity d => [d.horizontal, d.vertical],
  MouseCursor c => c.toString(),
  InteractiveInkFeatureFactory f => f.runtimeType.toString(),
  Duration d => d.inMicroseconds,
  Enum e => e.name,
  double d when !d.isFinite => d.toString(),
  num n => n,
  bool b => b,
  String s => s,
  _ => throw StateError('Unserialized theme value ${value.runtimeType}'),
};

Object? themeStates(WidgetStateProperty<Object?>? property) {
  if (property == null) return null;
  return {
    for (var mask = 0; mask < 1 << settingsThemeStates.length; mask++)
      [
        for (var bit = 0; bit < settingsThemeStates.length; bit++)
          if (mask & (1 << bit) != 0) settingsThemeStates[bit].name,
      ].join('+'): themeValue(
        property.resolve({
          for (var bit = 0; bit < settingsThemeStates.length; bit++)
            if (mask & (1 << bit) != 0) settingsThemeStates[bit],
        }),
      ),
  };
}

Map<String, Object?> themeButton(ButtonStyle s) => {
  'textStyle': themeStates(s.textStyle),
  'backgroundColor': themeStates(s.backgroundColor),
  'foregroundColor': themeStates(s.foregroundColor),
  'overlayColor': themeStates(s.overlayColor),
  'shadowColor': themeStates(s.shadowColor),
  'surfaceTintColor': themeStates(s.surfaceTintColor),
  'elevation': themeStates(s.elevation),
  'padding': themeStates(s.padding),
  'minimumSize': themeStates(s.minimumSize),
  'fixedSize': themeStates(s.fixedSize),
  'maximumSize': themeStates(s.maximumSize),
  'iconColor': themeStates(s.iconColor),
  'iconSize': themeStates(s.iconSize),
  'side': themeStates(s.side),
  'shape': themeStates(s.shape),
  'mouseCursor': themeStates(s.mouseCursor),
  'iconAlignment': themeValue(s.iconAlignment),
  'visualDensity': themeValue(s.visualDensity),
  'tapTargetSize': themeValue(s.tapTargetSize),
  'animationDuration': themeValue(s.animationDuration),
  'enableFeedback': s.enableFeedback,
  'alignment': themeValue(s.alignment),
  'splashFactory': themeValue(s.splashFactory),
  // styleFrom sets neither builder; reject a new callback rather than silently
  // giving different implementations the same serialized identity.
  'backgroundBuilder': s.backgroundBuilder == null
      ? null
      : throw StateError('Unexpected background builder'),
  'foregroundBuilder': s.foregroundBuilder == null
      ? null
      : throw StateError('Unexpected foreground builder'),
};

Map<String, Object?> settingsThemeTable(ThemeData t) => {
  'stateOrder': [for (final s in settingsThemeStates) s.name],
  'colorScheme': {
    'primary': themeValue(t.colorScheme.primary),
    'onPrimary': themeValue(t.colorScheme.onPrimary),
    'primaryContainer': themeValue(t.colorScheme.primaryContainer),
    'onPrimaryContainer': themeValue(t.colorScheme.onPrimaryContainer),
    'secondary': themeValue(t.colorScheme.secondary),
    'onSecondary': themeValue(t.colorScheme.onSecondary),
    'secondaryContainer': themeValue(t.colorScheme.secondaryContainer),
    'onSecondaryContainer': themeValue(t.colorScheme.onSecondaryContainer),
    'surface': themeValue(t.colorScheme.surface),
    'onSurface': themeValue(t.colorScheme.onSurface),
    'surfaceContainerHighest': themeValue(
      t.colorScheme.surfaceContainerHighest,
    ),
    'surfaceContainerHigh': themeValue(t.colorScheme.surfaceContainerHigh),
    'surfaceContainer': themeValue(t.colorScheme.surfaceContainer),
    'surfaceContainerLow': themeValue(t.colorScheme.surfaceContainerLow),
    'error': themeValue(t.colorScheme.error),
    'outline': themeValue(t.colorScheme.outline),
    'outlineVariant': themeValue(t.colorScheme.outlineVariant),
    'surfaceTint': themeValue(t.colorScheme.surfaceTint),
  },
  'scaffoldBackgroundColor': themeValue(t.scaffoldBackgroundColor),
  'appBar': {
    'backgroundColor': themeValue(t.appBarTheme.backgroundColor),
    'elevation': t.appBarTheme.elevation,
    'scrolledUnderElevation': t.appBarTheme.scrolledUnderElevation,
    'centerTitle': t.appBarTheme.centerTitle,
    'titleTextStyle': themeValue(t.appBarTheme.titleTextStyle),
  },
  'card': {
    'color': themeValue(t.cardTheme.color),
    'elevation': t.cardTheme.elevation,
    'shape': themeValue(t.cardTheme.shape),
  },
  'divider': {
    'color': themeValue(t.dividerTheme.color),
    'thickness': t.dividerTheme.thickness,
  },
  'listTile': {
    'iconColor': themeValue(t.listTileTheme.iconColor),
    'textColor': themeValue(t.listTileTheme.textColor),
  },
  'input': {
    'filled': t.inputDecorationTheme.filled,
    'fillColor': themeValue(t.inputDecorationTheme.fillColor),
    'hintStyle': themeValue(t.inputDecorationTheme.hintStyle),
    'labelStyle': themeValue(t.inputDecorationTheme.labelStyle),
    'prefixIconColor': themeValue(t.inputDecorationTheme.prefixIconColor),
    'suffixIconColor': themeValue(t.inputDecorationTheme.suffixIconColor),
    'border': themeValue(t.inputDecorationTheme.border),
    'enabledBorder': themeValue(t.inputDecorationTheme.enabledBorder),
    'focusedBorder': themeValue(t.inputDecorationTheme.focusedBorder),
    'errorBorder': themeValue(t.inputDecorationTheme.errorBorder),
    'focusedErrorBorder': themeValue(t.inputDecorationTheme.focusedErrorBorder),
    'contentPadding': themeValue(t.inputDecorationTheme.contentPadding),
  },
  'elevatedButton': themeButton(t.elevatedButtonTheme.style!),
  'filledButton': themeButton(t.filledButtonTheme.style!),
  'outlinedButton': themeButton(t.outlinedButtonTheme.style!),
  'textButton': themeButton(t.textButtonTheme.style!),
  'switch': {
    'thumbColor': themeStates(t.switchTheme.thumbColor),
    'trackColor': themeStates(t.switchTheme.trackColor),
    'trackOutlineColor': themeStates(t.switchTheme.trackOutlineColor),
  },
  'checkbox': {
    'fillColor': themeStates(t.checkboxTheme.fillColor),
    'side': themeValue(t.checkboxTheme.side),
    'shape': themeValue(t.checkboxTheme.shape),
  },
  'radio': {'fillColor': themeStates(t.radioTheme.fillColor)},
  'slider': {
    'activeTrackColor': themeValue(t.sliderTheme.activeTrackColor),
    'inactiveTrackColor': themeValue(t.sliderTheme.inactiveTrackColor),
    'thumbColor': themeValue(t.sliderTheme.thumbColor),
    'overlayColor': themeValue(t.sliderTheme.overlayColor),
  },
  'progress': {'color': themeValue(t.progressIndicatorTheme.color)},
  'tabBar': {
    'indicatorColor': themeValue(t.tabBarTheme.indicatorColor),
    'labelColor': themeValue(t.tabBarTheme.labelColor),
    'unselectedLabelColor': themeValue(t.tabBarTheme.unselectedLabelColor),
    'dividerColor': themeValue(t.tabBarTheme.dividerColor),
  },
  'dialog': {
    'backgroundColor': themeValue(t.dialogTheme.backgroundColor),
    'surfaceTintColor': themeValue(t.dialogTheme.surfaceTintColor),
    'shape': themeValue(t.dialogTheme.shape),
  },
  'popupMenu': {
    'color': themeValue(t.popupMenuTheme.color),
    'surfaceTintColor': themeValue(t.popupMenuTheme.surfaceTintColor),
    'shape': themeValue(t.popupMenuTheme.shape),
  },
  'bottomSheet': {
    'backgroundColor': themeValue(t.bottomSheetTheme.backgroundColor),
    'surfaceTintColor': themeValue(t.bottomSheetTheme.surfaceTintColor),
  },
  'snackBar': {'backgroundColor': themeValue(t.snackBarTheme.backgroundColor)},
  'chip': {
    'backgroundColor': themeValue(t.chipTheme.backgroundColor),
    'selectedColor': themeValue(t.chipTheme.selectedColor),
    'labelStyle': themeValue(t.chipTheme.labelStyle),
    'side': themeValue(t.chipTheme.side),
    'shape': themeValue(t.chipTheme.shape),
  },
  'dropdownMenu': {
    'backgroundColor': themeStates(
      t.dropdownMenuTheme.menuStyle!.backgroundColor,
    ),
    'surfaceTintColor': themeStates(
      t.dropdownMenuTheme.menuStyle!.surfaceTintColor,
    ),
    'shape': themeStates(t.dropdownMenuTheme.menuStyle!.shape),
  },
};
