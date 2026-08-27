import 'package:flutter/foundation.dart';

import '../core/http/gateway.dart';
import '../features/debrid/providers/alldebrid.dart';
import '../features/debrid/providers/pikpak.dart';
import '../features/debrid/providers/premiumize.dart';
import '../features/debrid/providers/real_debrid.dart';
import '../features/debrid/registry.dart';
import '../features/debrid/providers/torbox.dart';
import '../core/http/default_gateway.dart';
import '../features/pikpak/data/api_service.dart';

/// The app's long-lived services, built and wired in one place.
///
/// Every tuning decision that used to sit inline in a service lives here
/// instead — which timeout, which retry policy, which User-Agent. A service
/// declares what it needs in its constructor and is handed it; it does not
/// construct a transport of its own.
///
/// Build one directly in a test with whatever fakes it needs; production uses
/// [ServiceGraph.production].
class ServiceGraph {
  /// The app-wide transport: 15s, three attempts, one pooled connection set.
  final HttpGateway http;

  final PikPakApiService pikpak;

  /// PikPak's sign-in state, for widgets that rebuild on it. The notifier
  /// lives here rather than on the service: a service reports that something
  /// changed, it does not own the thing the UI listens to.
  final ValueNotifier<bool> pikpakAuthenticated;

  /// The debrid providers, already wired. The registry is an instance because
  /// its providers take dependencies; a `const` table could not.
  final DebridRegistry debrid;

  const ServiceGraph({
    required this.http,
    required this.pikpak,
    required this.pikpakAuthenticated,
    required this.debrid,
  });

  factory ServiceGraph.production() {
    final http = DefaultHttpGateway(userAgent: 'Debrify');

    // PikPak's own traffic gets a separate gateway. Its auth calls are one-shot
    // credential exchanges — repeating a signin burns the captcha token it
    // carries — so retries are off, and its endpoints are slower than the app
    // default allows for.
    final pikpakHttp = DefaultHttpGateway(
      userAgent: 'Debrify',
      defaultTimeout: const Duration(seconds: 20),
      defaultRetry: RetryPolicy.none,
    );

    final pikpakAuthenticated = ValueNotifier(false);
    final pikpak = PikPakApiService(
      http: pikpakHttp,
      publishAuth: (authenticated) => pikpakAuthenticated.value = authenticated,
    );

    return ServiceGraph(
      http: http,
      pikpak: pikpak,
      pikpakAuthenticated: pikpakAuthenticated,
      // Registration order is also the order pickers and settings list them in.
      debrid: DebridRegistry([
        RealDebridProvider(),
        TorboxProvider(),
        PremiumizeProvider(),
        AllDebridProvider(),
        PikPakProvider(drive: pikpak),
      ]),
    );
  }
}

/// Ambient access to the graph, for callers that have nowhere to inject yet.
///
/// A staging post, not the destination. Reading `AppServices.pikpak` instead of
/// a `static final instance` on the service already buys three things: a
/// service's dependencies are declared in its constructor rather than reached
/// for, every wiring decision sits in one readable file, and a test can replace
/// the whole graph in one call.
///
/// It is still globally reachable, so it is still a service locator. Callers
/// leave as they gain somewhere to take the dependency — screens when their
/// controllers land, the static services as they stop being static. When the
/// last one is injected this class goes and [ServiceGraph] stays.
abstract final class AppServices {
  static ServiceGraph _graph = ServiceGraph.production();

  /// Replace the whole graph. Pair with [reset] in tearDown.
  @visibleForTesting
  static void override(ServiceGraph graph) => _graph = graph;

  @visibleForTesting
  static void reset() => _graph = ServiceGraph.production();

  static HttpGateway get http => _graph.http;
  static PikPakApiService get pikpak => _graph.pikpak;

  /// Listen to this to rebuild when PikPak signs in or out.
  static ValueListenable<bool> get pikpakAuthenticated =>
      _graph.pikpakAuthenticated;
  static DebridRegistry get debrid => _graph.debrid;
}
