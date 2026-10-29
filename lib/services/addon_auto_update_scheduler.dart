// When the daily addon refresh runs: shortly after launch, then hourly while
// the app runs (a TV left on, a profile switched) and on return to the
// foreground. AddonAutoUpdate.runIfDue decides
// whether a pass is due for the active profile; this file only owns timing.
import 'dart:async';

import 'package:debrify/services/addon_auto_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final class AddonAutoUpdateScheduler with WidgetsBindingObserver {
  AddonAutoUpdateScheduler._();

  static final instance = AddonAutoUpdateScheduler._();

  /// Long enough for Home to finish its first catalog loads; a refreshed
  /// addon reloads catalogs, and launch traffic should not double.
  static const launchDelay = Duration(seconds: 90);

  /// A foreground return checks at most this often.
  static const resumeSpacing = Duration(hours: 1);

  bool _started = false;
  bool _running = false;
  Timer? _launchTimer;
  DateTime? _lastCheck;

  void start() {
    if (_started || kIsWeb) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _launchTimer = Timer(launchDelay, () {
      _check();
      // App-lifetime timer, like the scheduler itself.
      Timer.periodic(resumeSpacing, (_) => _check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (_launchTimer?.isActive ?? false) return;
    if (last != null && DateTime.now().difference(last) < resumeSpacing) {
      return;
    }
    _check();
  }

  void _check() {
    if (_running) return;
    _running = true;
    _lastCheck = DateTime.now();
    unawaited(
      AddonAutoUpdate.runIfDue()
          .then((outcome) {
            debugPrint('Addon auto-update: ${outcome.name}');
          })
          .catchError((Object error) {
            debugPrint('Addon auto-update failed: $error');
          })
          .whenComplete(() => _running = false),
    );
  }
}
