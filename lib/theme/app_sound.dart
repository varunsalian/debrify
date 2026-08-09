import 'package:flutter/material.dart';

/// What moving the cursor sounds like.
///
/// The dimension nobody photographs and everybody notices. A TV app that ticks
/// as you traverse feels like hardware; one that is silent feels like a web
/// page. It is also the dimension with the highest chance of being *worse*
/// than nothing, which is why the default is silence and why the dispatcher
/// in `ui_feedback.dart` demands causal evidence before it makes a sound.
enum SoundCharacter {
  /// No sound at all. Today's app, and the legacy pin.
  silent,

  /// A short, dry tick — the platform's own click. Reads as a mechanism.
  click,

  /// The platform's alert, reserved for activation rather than traversal.
  /// Never used for focus movement; a tick on every cell at this weight is
  /// unbearable within about ten seconds.
  soft,
}

/// What moving the cursor FEELS like.
///
/// Phone and tablet only, and not because of a policy: a TV remote has no
/// actuator, and `HapticFeedback` on a device without one is a channel call
/// that does nothing. The gate lives in [hapticFor] so no call site has to
/// remember it.
enum HapticCharacter {
  /// Nothing. Today's app for traversal, and the legacy pin.
  none,

  /// `HapticFeedback.selectionClick` — the lightest thing the platform has.
  selection,

  /// `HapticFeedback.lightImpact`. Heavier; for activation, not traversal.
  impact,
}

/// The feedback half of a look.
///
/// Two characters rather than a sound file per event: a theme that ships its
/// own audio assets is a theme that ships an APK-size regression, a licensing
/// question and a tvOS packaging problem, and none of those are what makes an
/// app feel expensive. What makes it feel expensive is that the tick happens
/// at the right instant and never at the wrong one — which is a dispatcher
/// problem, not an asset problem.
@immutable
class SoundTokens {
  /// The sound a cursor move makes.
  final SoundCharacter traversal;

  /// The sound an activation makes.
  final SoundCharacter activation;

  /// The haptic a cursor move makes, off TV.
  final HapticCharacter traversalHaptic;

  /// The haptic an activation makes, off TV.
  final HapticCharacter activationHaptic;

  const SoundTokens({
    required this.traversal,
    required this.activation,
    required this.traversalHaptic,
    required this.activationHaptic,
  });

  /// Today's app: silent, and no traversal haptic.
  ///
  /// A true no-op. The app DOES call `HapticFeedback` in about a dozen places
  /// today (the player's seek, the tuner's surf, the classic nav's tabs) —
  /// those are explicit site calls and this layer does not touch them. What
  /// legacy pins is that no NEW feedback appears anywhere.
  static const SoundTokens legacy = SoundTokens(
    traversal: SoundCharacter.silent,
    activation: SoundCharacter.silent,
    traversalHaptic: HapticCharacter.none,
    activationHaptic: HapticCharacter.none,
  );

  /// Traversal sound belongs to devices with a CURSOR.
  ///
  /// A TV remote and a desktop keyboard both traverse; a finger does not —
  /// there is nothing to move, and a tick per focus change would fire on every
  /// text field and every scroll restoration. Activation sound is not gated:
  /// a confirmation tone is meaningful anywhere.
  ///
  /// The parameter is `hasCursor`, not `isTv`, because those are two different
  /// questions and conflating them silenced every desktop user.
  SoundCharacter traversalFor(bool hasCursor) =>
      hasCursor ? traversal : SoundCharacter.silent;

  /// Haptics belong to devices with an ACTUATOR — a phone or a tablet.
  ///
  /// Not "not a TV": a desktop has no vibration motor either, and asking it
  /// to buzz is a channel call into nothing. A TV remote is the same story.
  HapticCharacter hapticFor(bool hasActuator, {required bool activation}) {
    if (!hasActuator) return HapticCharacter.none;
    return activation ? activationHaptic : traversalHaptic;
  }

  bool get isSilent =>
      traversal == SoundCharacter.silent &&
      activation == SoundCharacter.silent &&
      traversalHaptic == HapticCharacter.none &&
      activationHaptic == HapticCharacter.none;
}

/// A look's feedback, as ONE decision.
///
/// `SoundTokens` has four fields; a spec author has one opinion. Exposing the
/// four separately invites the incoherent combination — a silent traversal
/// with a heavy activation haptic — for no expressive gain, so the spec picks
/// a character and this maps it.
enum FeedbackCharacter {
  /// Nothing. The default, and the legacy pin.
  none,

  /// Traversal ticks on TV, selection haptic on phone. The "this is hardware"
  /// setting.
  mechanical,

  /// Silent traversal, but activation confirms — on both platforms. For a
  /// look that wants weight without chatter.
  confirming,
}

/// The character → tokens mapping, in one place.
SoundTokens soundTokensFor(FeedbackCharacter c) => switch (c) {
  FeedbackCharacter.none => SoundTokens.legacy,
  FeedbackCharacter.mechanical => const SoundTokens(
    traversal: SoundCharacter.click,
    activation: SoundCharacter.click,
    traversalHaptic: HapticCharacter.selection,
    activationHaptic: HapticCharacter.impact,
  ),
  FeedbackCharacter.confirming => const SoundTokens(
    traversal: SoundCharacter.silent,
    activation: SoundCharacter.click,
    traversalHaptic: HapticCharacter.none,
    activationHaptic: HapticCharacter.impact,
  ),
};
