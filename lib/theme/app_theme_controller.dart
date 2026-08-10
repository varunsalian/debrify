import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/text_brightness.dart';
import '../widgets/detail/theme/detail_themes.dart';
import 'app_theme.dart';
import 'premium_looks.dart';
import 'app_theme_adapter.dart';
import 'theme_core_resolver.dart';
import 'theme_override_applier.dart';
import 'theme_overrides.dart';

/// Owns the live app theme: the selected id, the preset-resolved [AppTheme]
/// the scope provides, and the [ThemeData] the root `MaterialApp` renders.
///
/// **Everything is memoized here, never built in `build()`.** `ThemeData`
/// construction is a large allocation plus colour math; on a Mi-Box-class
/// GPU/CPU doing it per rebuild is a real cost. The derived pair is recomputed
/// exactly once per (theme id × text-brightness preset) change and cached —
/// a rebuild only ever reads fields.
class AppThemeController extends ChangeNotifier {
  AppThemeController._() {
    // The preset is an input to both derived values, so preset changes flow
    // through the same recompute path as theme changes. DebrifyApp also
    // listens to the preset notifier directly (its long-standing pattern);
    // the double notification is two cheap reads, not two ThemeData builds.
    TextBrightnessController.notifier.addListener(_recompute);
  }

  static final AppThemeController instance = AppThemeController._();

  String _id = AppThemes.legacyId;

  // Memoized derived state — see class doc. The ThemeData initializer routes
  // through [legacyThemeData] so a pre-warm read, warm() itself and the first
  // LegacyThemeBoundary all share ONE legacy build per preset — startup pays
  // exactly the single ThemeData construction it paid before this layer.
  late AppTheme _theme = AppThemes.legacy;
  late ThemeData _themeData = legacyThemeData;

  /// Monotonic token for [select]'s persistence: each call takes the next
  /// value, and a call that finds itself superseded after an await stops
  /// writing. Without it, two overlapping selects could interleave their
  /// awaits and persist the older choice last — correct on screen
  /// (publish-first is synchronous) but wrong again after restart.
  ///
  /// Deliberately a token, NOT a stored Future chain: a chained future on a
  /// process-lifetime singleton is bound to the zone that extended it, and a
  /// later `.then` from another zone (widget tests' FakeAsync above all)
  /// deadlocks on the dead zone's microtask queue.
  int _persistSeq = 0;

  // The frozen profile every LegacyThemeBoundary shadows with. Cached per
  // preset for the same reason as above: a dozen boundaries must not mean a
  // dozen ThemeData builds.
  TextBrightness? _legacyPreset;
  ThemeData? _legacyThemeData;

  String get id => _id;
  bool get isLegacy => _id == AppThemes.legacyId;

  /// The preset-resolved theme the root [AppThemeScope] provides.
  AppTheme get theme => _theme;

  /// The root `MaterialApp.theme`. Under `legacy`, byte-for-byte the theme
  /// the app has always shipped.
  ThemeData get themeData => _themeData;

  /// What every freeze boundary renders: legacy tokens…
  AppTheme get legacyTheme => AppThemes.legacy;

  /// …and today's root ThemeData at the CURRENT text-brightness preset —
  /// frozen surfaces keep following the preset exactly as they always have.
  ThemeData get legacyThemeData {
    final preset = TextBrightnessController.current;
    if (_legacyThemeData == null || _legacyPreset != preset) {
      _legacyPreset = preset;
      _legacyThemeData = AppThemeAdapter.legacy(preset);
    }
    return _legacyThemeData!;
  }

  /// Load the stored choice. Called in main() before runApp, AFTER
  /// `TextBrightnessController.warm()` — the preset is an input here. Swallows
  /// storage failures: a cosmetic pref must never keep the app from starting,
  /// and the fields already hold the legacy default.
  static Future<void> warm() async {
    try {
      instance._id = await StorageService.getAppTheme();
      // Decoded here rather than on every recompute: a malformed value costs
      // one parse at startup and degrades to none, and the running app never
      // touches storage to answer "what did the user change".
      instance._overrides =
          ThemeOverrides.decode(await StorageService.getThemeOverrides());
      instance._recomputeSilently();
    } catch (e) {
      debugPrint('AppThemeController: warm failed, staying legacy: $e');
    }
  }

  /// Apply a choice live, then persist it. Publish-first, like the
  /// text-brightness controller: rapid re-selections apply in tap order, and
  /// a failed write costs only stickiness across restart.
  ///
  /// Persist order is the write-through contract: for a real theme the
  /// `detail_theme` mirror lands FIRST, then `app_theme` — old builds read
  /// only the mirror, so a crash between the writes leaves them consistent.
  /// Selecting `legacy` writes no mirror: details returns to whatever the
  /// mirror last was, and the picker UI says so.
  Future<void> select(String id) async {
    final normalized =
        (id == AppThemes.legacyId || StorageService.kDetailThemes.contains(id))
        ? id
        : AppThemes.legacyId;
    // NOT `normalized == _id` alone. `select` also writes the `detail_theme`
    // mirror, so this sequence left a Look half-applied: apply it, change
    // Details Theme by hand, apply it again — the app theme already matches,
    // this returns, and the mirror is never repaired. Compare BOTH.
    final mirrorOk = normalized == AppThemes.legacyId ||
        StorageService.detailThemeCached == normalized;
    if (normalized == _id && mirrorOk) return;
    _id = normalized;
    if (normalized != AppThemes.legacyId) {
      // The synchronous mirror BEFORE publishing: an open details route
      // rebuilds on the notify below and reads this cache — updating it only
      // when the async write lands would leave that route on the stale theme
      // with no later notification. A failed write then costs stickiness
      // across restart, never on-screen state (setDetailTheme re-assigns the
      // same value when it completes).
      StorageService.detailThemeCached = normalized;
    }
    _recompute();
    final seq = ++_persistSeq;
    try {
      if (normalized != AppThemes.legacyId) {
        await StorageService.setDetailTheme(normalized);
        // Superseded mid-flight: the newer select owns the final state, and
        // writing app_theme now could land AFTER its writes. Our detail write
        // is harmless — the newer call's own detail write was issued later
        // and the preference channel is FIFO, so it wins the key.
        if (seq != _persistSeq) return;
      }
      await StorageService.setAppTheme(normalized);
    } catch (e) {
      debugPrint('AppThemeController: persist failed: $e');
    }
  }

  void _recompute() {
    _recomputeSilently();
    notifyListeners();
  }

  /// The user's per-token edits. Read from the cached preference so a rebuild
  /// never touches storage; refreshed by [warm] and by [setOverrides].
  ThemeOverrides _overrides = ThemeOverrides.none;

  ThemeOverrides get overrides => _overrides;

  /// Apply an edited token set live, then persist it.
  ///
  /// Publish-first, exactly like [select]: the recompute and notify happen
  /// synchronously so the app re-themes on the next frame, and a failed write
  /// costs only stickiness across a restart.
  ///
  /// This is the ONLY invalidation path for overrides. [select] returns early
  /// when the theme id has not changed, so routing an override change through
  /// it would clear storage and leave the edited pixels on screen.
  Future<void> setOverrides(ThemeOverrides value) async {
    if (value.encode() == _overrides.encode()) return;
    _overrides = value;
    _recompute();
    // No sequence token here, unlike [select] — and deliberately not one shared
    // with it.
    //
    // `select` needs one because it writes TWO keys and a superseded call must
    // not interleave them. This writes one key, after no awaits, and the mirror
    // is published before the write; the preference channel is FIFO, so the
    // last caller's value lands last. A token here would have been a guard that
    // could never fire, which is worse than none because it implies protection.
    //
    // Sharing `select`'s token WAS actively harmful: an override change landing
    // mid-select made select bail after writing `detail_theme` and never write
    // `app_theme`, leaving the two disagreeing after a restart.
    try {
      await StorageService.setThemeOverrides(value.encode());
    } catch (e) {
      debugPrint('AppThemeController: override persist failed: $e');
    }
  }

  Future<void> clearOverrides() => setOverrides(ThemeOverrides.none);

  void _recomputeSilently() {
    final preset = TextBrightnessController.current;
    // Classic is deliberately NOT editable: it is a hand-built theme whose
    // token groups are no-ops by construction, which is what makes it the
    // honest "unthemed" option rather than a theme with nothing to edit.
    if (_id == AppThemes.legacyId) {
      _theme = AppThemes.legacy;
      // Via the per-preset cache, NOT a fresh build — under legacy the root
      // theme and every boundary's frozen theme are the same object.
      _themeData = legacyThemeData;
      return;
    }
    // Preset first, then derivation: subprofile tones (settings.dim etc.) are
    // computed FROM the resolved text colour, so the whole token surface
    // follows the preset, not just Material's onSurface.
    final overrides = _overrides;
    // Colour, shape, type and grain reach the CORE, and must be applied before
    // the preset resolves — every derived surface tone is computed from them,
    // and the preset still has to have the last word on text.
    //
    // Through the shared resolver rather than inline: the detail layouts fetch
    // their core from the same place, and a core patched only here would leave
    // every alternate detail page showing the unedited theme.
    final core = AppThemeAdapter.resolveCoreText(
      ThemeCoreResolver.resolve(_id, overrides),
      preset,
    );
    // A premium look is a SPEC, and `fromDetail(core)` alone would deliver
    // only its colours — the separation model, the scrim grammar, the focus
    // expression, the grade, the motion character and the feedback all live
    // in the phase-four groups that only `ThemeSpec` supplies. Resolving them
    // here rather than in `AppThemes.byId` is what actually puts them on
    // screen: this is the method the live app reads.
    final spec = PremiumLooks.byId(_id);
    if (spec != null) {
      _theme = overrides.isEmpty
          ? spec.buildWith(core)
          : ThemeOverrideApplier.applyToSpec(spec, overrides).buildWith(core);
    } else if (overrides.isEmpty) {
      _theme = AppTheme.fromDetail(core);
    } else {
      _theme = ThemeOverrideApplier.buildFromDetail(
        core,
        overrides,
        authored: AppThemeAdapter.resolveCoreText(
          DetailThemes.byId(_id),
          preset,
        ),
      );
    }
    _themeData = AppThemeAdapter.themed(_theme, preset);
  }
}
