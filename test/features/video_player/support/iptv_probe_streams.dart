import 'dart:async';

/// Observes real listen/cancel calls at the fake player's stream boundary.
/// Existing subscribers remain independent of the candidate probe's leases.
class IptvProbeStream<T> extends Stream<T> {
  IptvProbeStream(this.source);
  final Stream<T> source;
  final leases = <IptvProbeSubscription<T>>[];
  int get active => leases.where((s) => !s.cancelled).length;
  @override
  bool get isBroadcast => source.isBroadcast;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final lease = IptvProbeSubscription(
      source.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
    );
    leases.add(lease);
    return lease;
  }
}

class IptvProbeSubscription<T> implements StreamSubscription<T> {
  IptvProbeSubscription(this.source);
  final StreamSubscription<T> source;
  final owner = StackTrace.current.toString();
  bool cancelled = false;
  @override
  Future<void> cancel() {
    cancelled = true;
    return source.cancel();
  }

  @override
  bool get isPaused => source.isPaused;
  @override
  void onData(void Function(T)? handler) => source.onData(handler);
  @override
  void onError(Function? handler) => source.onError(handler);
  @override
  void onDone(void Function()? handler) => source.onDone(handler);
  @override
  void pause([Future<void>? resumeSignal]) => source.pause(resumeSignal);
  @override
  void resume() => source.resume();
  @override
  Future<E> asFuture<E>([E? value]) => source.asFuture(value);
}

/// Only the controller operations exercised by FakePlayer are adapted; all
/// event delivery and broadcast semantics belong to the real controller.
class IptvProbeController<T> implements StreamController<T> {
  final source = StreamController<T>.broadcast();
  late final observed = IptvProbeStream(source.stream);
  @override
  Stream<T> get stream => observed;
  @override
  void add(T event) => source.add(event);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      source.addError(error, stackTrace);
  @override
  bool get isClosed => source.isClosed;
  @override
  bool get hasListener => source.hasListener;
  @override
  bool get isPaused => source.isPaused;
  @override
  Future<void> get done => source.done;
  @override
  Future<void> close() => source.close();
  @override
  Future<void> addStream(Stream<T> stream, {bool? cancelOnError}) =>
      source.addStream(stream, cancelOnError: cancelOnError);
  @override
  StreamSink<T> get sink => source.sink;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
