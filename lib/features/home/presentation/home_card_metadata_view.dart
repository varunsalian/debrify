import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_card_metadata_controller.dart';
import '../application/home_card_metadata_dependencies.dart';
import '../models/home_card_metadata.dart';

/// Binds one mounted card to its metadata state without owning card focus/animation.
class HomeCardMetadataView extends ConsumerStatefulWidget {
  const HomeCardMetadataView({
    super.key,
    required this.original,
    required this.builder,
  });
  final StremioMeta original;
  final Widget Function(BuildContext, HomeCardMetadataState) builder;

  @override
  ConsumerState<HomeCardMetadataView> createState() =>
      _HomeCardMetadataViewState();
}

class _HomeCardMetadataViewState extends ConsumerState<HomeCardMetadataView> {
  final _identity = Object();
  int _generation = 0;
  bool _retired = false;
  late final HomeCardMetadataEpoch _initialEpoch;
  late final ProviderSubscription<HomeCardMetadataEpoch> _epochSubscription;
  ProviderSubscription<HomeCardMetadataState>? _subscription;
  late HomeCardMetadataController _controller;
  late HomeCardMetadataSession _session;

  @override
  void initState() {
    super.initState();
    _epochSubscription = ref.listenManual(homeCardMetadataEpochProvider, (
      _,
      epoch,
    ) {
      if (!mounted || _retired) return;
      _bind(epoch, preserve: false);
      setState(() {});
    });
    _initialEpoch = _epochSubscription.read();
    _bind(_initialEpoch, preserve: false);
  }

  void _bind(HomeCardMetadataEpoch epoch, {required bool preserve}) {
    if (_retired) return;
    if (epoch.owner != _initialEpoch.owner) {
      _retired = true;
      _controller.retire();
      _subscription?.close();
      _subscription = null;
      return;
    }
    final previous = _subscription?.read();
    if (_subscription != null) {
      _controller.retire();
      _subscription!.close();
    }
    final initial = preserve && previous != null && _session.epoch == epoch
        ? previous.forSource(widget.original)
        : HomeCardMetadataState(original: widget.original);
    final session = _session = HomeCardMetadataSession(
      epoch: epoch,
      viewIdentity: _identity,
      generation: ++_generation,
      initial: initial,
    );
    final provider = homeCardMetadataProvider(session);
    _subscription = ref.listenManual(provider, (_, next) {
      if (mounted && !_retired) setState(() {});
    });
    _controller = ref.read(provider.notifier);
    unawaited(
      _controller.load(
        isCurrent: () => mounted && !_retired && identical(_session, session),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant HomeCardMetadataView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_retired || identical(oldWidget.original, widget.original)) return;
    _bind(_epochSubscription.read(), preserve: true);
  }

  @override
  void dispose() {
    _controller.retire();
    _subscription?.close();
    _epochSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _retired
      ? const SizedBox.shrink()
      : widget.builder(context, _subscription!.read());
}
