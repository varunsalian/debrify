import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Stream/IOSink facade over a retained raw transport. Keeping the RawSocket
/// lets the connection owner cancel TLS even before the handshake completes.
class TmdbTransportSocket extends Stream<Uint8List> implements Socket {
  TmdbTransportSocket(this.transport) {
    _input = StreamController<Uint8List>(
      onListen: _listen,
      onPause: () => transport.readEventsEnabled = false,
      onResume: () => transport.readEventsEnabled = true,
      onCancel: destroy,
    );
    _sink = IOSink(_SocketConsumer(this));
  }
  final RawSocket transport;
  late final StreamController<Uint8List> _input;
  late final IOSink _sink;
  StreamSubscription<RawSocketEvent>? _events;
  Completer<void>? _writable;
  bool _destroyed = false;

  void _listen() {
    if (_events != null || _destroyed) return;
    _events = transport.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          final bytes = transport.read();
          if (bytes != null) _input.add(bytes);
        } else if (event == RawSocketEvent.write) {
          final pending = _writable;
          _writable = null;
          pending?.complete();
        } else if (event == RawSocketEvent.readClosed) {
          _input.close();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_input.isClosed) _input.addError(error, stack);
        destroy();
      },
      onDone: destroy,
    );
  }

  Future<void> send(List<int> bytes) async {
    _listen();
    var offset = 0;
    while (offset < bytes.length) {
      if (_destroyed) throw const SocketException('Connection closed');
      offset += transport.write(bytes, offset, bytes.length - offset);
      if (offset < bytes.length) {
        final pending = _writable ??= Completer<void>();
        transport.writeEventsEnabled = true;
        await pending.future;
      }
    }
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    // Resolve blocked writes; their next iteration reports closure.
    _writable?.complete();
    _writable = null;
    transport.close();
    _events?.cancel();
    if (!_input.isClosed) _input.close();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  Future<void> flush() => _sink.flush();
  @override
  Future<Socket> close() async {
    await _sink.close();
    return this;
  }

  @override
  Future get done => _sink.done;
  @override
  InternetAddress get address => transport.address;
  @override
  InternetAddress get remoteAddress => transport.remoteAddress;
  @override
  int get port => transport.port;
  @override
  int get remotePort => transport.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      transport.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      transport.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => transport.setRawOption(option);
}

class _SocketConsumer implements StreamConsumer<List<int>> {
  _SocketConsumer(this.socket);
  final TmdbTransportSocket socket;
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      await socket.send(bytes);
    }
  }

  @override
  Future<void> close() async {
    if (!socket._destroyed) socket.transport.shutdown(SocketDirection.send);
  }
}
