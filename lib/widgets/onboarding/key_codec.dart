import 'package:flutter/services.dart';

typedef KeyParse = ({String key, bool hideFromNav});

const _nonavPrefix = 'nonav:';

/// Removes visual grouping and preserves the provisioning-only nonav side
/// effect as data rather than silently discarding it.
KeyParse parseOnboardingKey(String raw) {
  // Whitespace is visual grouping, including whitespace that may have been
  // inserted while the provisioning prefix was being typed incrementally.
  var value = raw.trim().replaceAll(RegExp(r'\s+'), '');
  var hideFromNav = false;
  if (value.toLowerCase().startsWith(_nonavPrefix)) {
    hideFromNav = true;
    value = value.substring(_nonavPrefix.length);
  }
  return (key: value, hideFromNav: hideFromNav);
}

String groupOnboardingKey(String payload) {
  final clean = payload.replaceAll(RegExp(r'\s+'), '');
  final groups = <String>[];
  for (var i = 0; i < clean.length; i += 4) {
    final end = i + 4 < clean.length ? i + 4 : clean.length;
    groups.add(clean.substring(i, end));
  }
  return groups.join(' ');
}

String formatOnboardingKey(String raw) {
  final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
  // Until the colon arrives, keep a possible `nonav:` prefix intact. Grouping
  // `nonav` as `nona v` makes character-by-character entry impossible.
  if (compact.isNotEmpty &&
      compact.length < _nonavPrefix.length &&
      _nonavPrefix.startsWith(compact.toLowerCase())) {
    return compact;
  }
  final parsed = parseOnboardingKey(raw);
  final grouped = groupOnboardingKey(parsed.key);
  return parsed.hideFromNav ? '$_nonavPrefix$grouped' : grouped;
}

class OnboardingKeyFormatter extends TextInputFormatter {
  const OnboardingKeyFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatOnboardingKey(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
