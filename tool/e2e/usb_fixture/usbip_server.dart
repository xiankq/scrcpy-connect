// A hardware-free USB/IP ADB peer for isolated integration environments.
// USB/IP framing: https://www.kernel.org/doc/html/latest/usb/usbip_protocol.html
// The default ADB peer is simulated; targetHost/targetPort uses a real adbd.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class UsbIpAdbServer {
  UsbIpAdbServer._(this._listener, this.targetHost, this.targetPort, this.log);

  static Future<UsbIpAdbServer> start({
    InternetAddress? address,
    int port = 0,
    String? targetHost,
    int? targetPort,
    void Function(String)? log,
  }) async {
    if ((targetHost == null) != (targetPort == null)) {
      throw ArgumentError(
        'targetHost and targetPort must be supplied together',
      );
    }
    final listener = await ServerSocket.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final server = UsbIpAdbServer._(listener, targetHost, targetPort, log);
    listener.listen((socket) {
      final connection = _Connection(server, socket);
      server._connections.add(connection);
      connection.start();
    });
    return server;
  }

  final ServerSocket _listener;
  final String? targetHost;
  final int? targetPort;
  final void Function(String)? log;
  final Set<_Connection> _connections = {};
  _Connection? _imported;
  int get port => _listener.port;
  InternetAddress get address => _listener.address;
  String get busId => '1-1';
  bool get simulated => targetHost == null;

  Future<void> close() async {
    await _listener.close();
    for (final connection in _connections.toList()) {
      connection.close();
    }
  }
}

class _Urb {
  _Urb(this.sequence, this.direction, this.endpoint, this.length, this.setup);
  final int sequence, direction, endpoint, length;
  final Uint8List setup;
}

class _Transfer {
  _Transfer(this.bytes);
  final Uint8List bytes;
  int offset = 0;
}

class _Connection {
  _Connection(this.server, this.socket);
  final UsbIpAdbServer server;
  final Socket socket;
  Uint8List _buffer = Uint8List(0);
  Uint8List _adbBuffer = Uint8List(0);
  final Queue<_Urb> _reads = Queue();
  final Queue<_Transfer> _transfers = Queue();
  final Map<int, int> _streams = {};
  Socket? _target;
  bool _processing = false, _imported = false, _closed = false;
  int _configuration = 0, _nextStream = 1;
  int _queuedBytes = 0;
  static const _limit = 16 * 1024 * 1024;

  void start() {
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.listen(
      (bytes) {
        if (_closed) return;
        _buffer = Uint8List.fromList([..._buffer, ...bytes]);
        if (_buffer.length > _limit + 48) {
          close();
        } else {
          unawaited(_process());
        }
      },
      onError: (Object _) => close(),
      onDone: close,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    socket.destroy();
    _target?.destroy();
    _reads.clear();
    _transfers.clear();
    _streams.clear();
    _buffer = Uint8List(0);
    _adbBuffer = Uint8List(0);
    _queuedBytes = 0;
    server._connections.remove(this);
    if (server._imported == this) server._imported = null;
    server.log?.call('usbip disconnected');
  }

  Uint8List _take(int count) {
    final bytes = Uint8List.sublistView(_buffer, 0, count);
    _buffer = Uint8List.sublistView(_buffer, count);
    return bytes;
  }

  Future<void> _process() async {
    if (_processing || _closed) return;
    _processing = true;
    try {
      while (!_closed) {
        if (!_imported) {
          if (_buffer.length < 8) break;
          final header = ByteData.sublistView(_buffer);
          final operation = header.getUint16(2);
          if (header.getUint16(0) != 0x111) {
            close();
            break;
          }
          if (operation == 0x8005) {
            _take(8);
            socket.add(_operation(5, 0));
            socket.add(_u32(1));
            socket.add(_device());
            socket.add([0xff, 0x42, 1, 0]);
            await socket.flush();
            close();
            break;
          }
          if (operation != 0x8003) {
            close();
            break;
          }
          if (_buffer.length < 40) break;
          final request = _take(40);
          final busId = ascii.decode(
            request.sublist(8).takeWhile((b) => b != 0).toList(),
          );
          if (busId != server.busId || server._imported != null) {
            socket.add(_operation(3, 1));
            await socket.flush();
            close();
            break;
          }
          server._imported = this;
          if (!server.simulated) {
            try {
              _target = await Socket.connect(
                server.targetHost,
                server.targetPort!,
                timeout: const Duration(seconds: 5),
              );
            } on Object {
              socket.add(_operation(3, 1));
              await socket.flush();
              close();
              break;
            }
            if (_closed) {
              _target!.destroy();
              break;
            }
            _target!.setOption(SocketOption.tcpNoDelay, true);
            _target!.listen(
              _receiveAdb,
              onError: (Object _) => close(),
              onDone: close,
            );
          }
          socket.add(_operation(3, 0));
          socket.add(_device());
          _imported = true;
          server.log?.call(
            'usbip imported mode=${server.simulated ? 'simulated' : 'adbd'}',
          );
          continue;
        }
        if (_buffer.length < 48) break;
        final header = ByteData.sublistView(_buffer);
        final command = header.getUint32(0);
        if (command == 2) {
          final sequence = header.getUint32(4);
          final target = header.getUint32(20);
          final found = _reads.any((urb) => urb.sequence == target);
          _reads.removeWhere((urb) => urb.sequence == target);
          _take(48);
          final response = Uint8List(48);
          final view = ByteData.sublistView(response);
          view.setUint32(0, 4);
          view.setUint32(4, sequence);
          view.setInt32(20, found ? -104 : 0);
          socket.add(response);
          server.log?.call('usbip unlink canceled=${found ? 1 : 0}');
          continue;
        }
        if (command != 1) {
          close();
          break;
        }
        final direction = header.getUint32(12);
        final length = header.getInt32(24);
        final packets = header.getInt32(32);
        if (direction > 1 || length < 0 || length > _limit || packets > 0) {
          close();
          break;
        }
        final frameLength = 48 + (direction == 0 ? length : 0);
        if (_buffer.length < frameLength) break;
        final urb = _Urb(
          header.getUint32(4),
          direction,
          header.getUint32(16),
          length,
          Uint8List.fromList(_buffer.sublist(40, 48)),
        );
        final frame = _take(frameLength);
        if (urb.endpoint == 0) {
          _control(urb);
        } else if (urb.endpoint != 1) {
          _reply(urb, status: -32);
        } else if (urb.direction == 1) {
          if (_reads.length >= 256) {
            close();
            break;
          }
          _reads.add(urb);
          _drain();
        } else {
          final bytes = Uint8List.sublistView(frame, 48);
          if (_target != null) {
            _target!.add(bytes);
          } else {
            _receiveSimulated(bytes);
          }
          _reply(urb, actual: bytes.length);
        }
      }
    } on Object {
      // Never print ADB data, services, AUTH material or exception payloads.
      server.log?.call('usbip protocol failure');
      close();
    } finally {
      _processing = false;
    }
  }

  void _reply(_Urb urb, {Uint8List? bytes, int? actual, int status = 0}) {
    if (_closed) return;
    final response = Uint8List(48);
    final view = ByteData.sublistView(response);
    view.setUint32(0, 3);
    view.setUint32(4, urb.sequence);
    view.setInt32(20, status);
    view.setUint32(24, actual ?? bytes?.length ?? 0);
    socket.add(response);
    if (bytes != null && urb.direction == 1) socket.add(bytes);
  }

  void _control(_Urb urb) {
    final setup = ByteData.sublistView(urb.setup);
    final request = urb.setup[1];
    final value = setup.getUint16(2, Endian.little);
    final length = setup.getUint16(6, Endian.little);
    Uint8List? bytes;
    if (request == 6 && urb.direction == 1) {
      bytes = _descriptor(value >> 8, value & 255);
    } else if (request == 9 && value <= 1 && urb.direction == 0) {
      _configuration = value;
      bytes = Uint8List(0);
      server.log?.call('usbip configured value=$value');
    } else if (request == 8 && urb.direction == 1) {
      bytes = Uint8List.fromList([_configuration]);
    } else if (request == 0 && urb.direction == 1) {
      bytes = Uint8List(2);
    } else if (request == 10 && urb.direction == 1) {
      bytes = Uint8List(1);
    } else if ((request == 1 ||
            request == 3 ||
            request == 5 ||
            request == 11) &&
        urb.direction == 0) {
      bytes = Uint8List(0);
    }
    if (bytes == null) {
      _reply(urb, status: -32);
    } else {
      _reply(
        urb,
        bytes: Uint8List.sublistView(
          bytes,
          0,
          math.min(bytes.length, math.min(length, urb.length)),
        ),
      );
    }
  }

  void _queueTransfer(Uint8List bytes) {
    _queuedBytes += bytes.length;
    if (_queuedBytes > _limit || _transfers.length > 4096) {
      close();
      return;
    }
    _transfers.add(_Transfer(bytes));
    // A full final USB packet is followed by a ZLP to end the transfer.
    if (bytes.isNotEmpty && bytes.length % 512 == 0) {
      _transfers.add(_Transfer(Uint8List(0)));
    }
  }

  void _drain() {
    while (_reads.isNotEmpty && _transfers.isNotEmpty && !_closed) {
      final urb = _reads.removeFirst();
      final transfer = _transfers.first;
      final remaining = transfer.bytes.length - transfer.offset;
      final count = math.min(remaining, urb.length);
      final bytes = Uint8List.sublistView(
        transfer.bytes,
        transfer.offset,
        transfer.offset + count,
      );
      transfer.offset += count;
      _queuedBytes -= count;
      if (transfer.offset == transfer.bytes.length) {
        _transfers.removeFirst();
        if (remaining > 0 &&
            count < urb.length &&
            count % 512 == 0 &&
            _transfers.isNotEmpty &&
            _transfers.first.bytes.isEmpty) {
          _transfers.removeFirst();
        }
      }
      _reply(urb, bytes: bytes);
    }
  }

  void _receiveAdb(List<int> bytes) => _consumeAdb(bytes, (header, payload) {
    _queueTransfer(header);
    if (payload.isNotEmpty) _queueTransfer(payload);
    _drain();
  });

  void _receiveSimulated(List<int> bytes) => _consumeAdb(bytes, (
    header,
    payload,
  ) {
    final view = ByteData.sublistView(header);
    final command = ascii.decode(header.sublist(0, 4));
    final arg0 = view.getUint32(4, Endian.little);
    final arg1 = view.getUint32(8, Endian.little);
    if (command == 'CNXN') {
      _sendAdb(
        'CNXN',
        0x01000001,
        1024 * 1024,
        utf8.encode(
          'device::ro.product.name=connect_fixture;ro.product.model=VirtualAndroid;ro.product.device=connect_fixture;features=shell_v2;\x00',
        ),
      );
      server.log?.call('adb simulated connected');
    } else if (command == 'OPEN') {
      final id = _nextStream++;
      _streams[id] = arg0;
      final service = utf8
          .decode(payload, allowMalformed: true)
          .replaceAll('\x00', '');
      _sendAdb('OKAY', id, arg0, []);
      final output = utf8.encode(_shellOutput(service));
      if (service.startsWith('shell,v2,') || service.startsWith('shell,v2:')) {
        final framed = BytesBuilder();
        if (output.isNotEmpty) {
          framed.add([1, ..._u32le(output.length), ...output]);
        }
        framed.add([3, 1, 0, 0, 0, 0]);
        _sendAdb('WRTE', id, arg0, framed.takeBytes());
      } else if (output.isNotEmpty) {
        _sendAdb('WRTE', id, arg0, output);
      } else {
        _streams.remove(id);
        _sendAdb('CLSE', id, arg0, []);
      }
      server.log?.call('adb simulated service opened bytes=${output.length}');
    } else if (command == 'OKAY' && _streams[arg1] == arg0) {
      _streams.remove(arg1);
      _sendAdb('CLSE', arg1, arg0, []);
    } else if (command == 'WRTE' && _streams[arg1] == arg0) {
      _sendAdb('OKAY', arg1, arg0, []);
    } else if (command == 'CLSE') {
      _streams.remove(arg1);
    }
  });

  void _consumeAdb(
    List<int> bytes,
    void Function(Uint8List, Uint8List) consume,
  ) {
    if (_closed) return;
    _adbBuffer = Uint8List.fromList([..._adbBuffer, ...bytes]);
    while (_adbBuffer.length >= 24) {
      final view = ByteData.sublistView(_adbBuffer);
      final length = view.getUint32(12, Endian.little);
      if (length > _limit ||
          view.getUint32(20, Endian.little) !=
              (view.getUint32(0, Endian.little) ^ 0xffffffff)) {
        close();
        return;
      }
      if (_adbBuffer.length < length + 24) return;
      final header = Uint8List.fromList(_adbBuffer.sublist(0, 24));
      final payload = Uint8List.fromList(_adbBuffer.sublist(24, length + 24));
      _adbBuffer = Uint8List.sublistView(_adbBuffer, length + 24);
      consume(header, payload);
      if (_closed) return;
    }
  }

  void _sendAdb(String command, int arg0, int arg1, List<int> payload) {
    final header = Uint8List(24);
    header.setRange(0, 4, ascii.encode(command));
    final view = ByteData.sublistView(header);
    view.setUint32(4, arg0, Endian.little);
    view.setUint32(8, arg1, Endian.little);
    view.setUint32(12, payload.length, Endian.little);
    // CNXN uses legacy checksum; retaining it is accepted by modern peers too.
    view.setUint32(
      16,
      payload.fold<int>(0, (a, b) => (a + b) & 0xffffffff),
      Endian.little,
    );
    view.setUint32(
      20,
      view.getUint32(0, Endian.little) ^ 0xffffffff,
      Endian.little,
    );
    _queueTransfer(header);
    if (payload.isNotEmpty) _queueTransfer(Uint8List.fromList(payload));
    _drain();
  }
}

String _shellOutput(String service) {
  final colon = service.indexOf(':');
  if (colon < 0) return '';
  final command = service.substring(colon + 1).trim();
  // The application uses a fixed list of getprop commands. Avoid treating
  // semicolons inside quoted echo/printf strings as shell syntax.
  if (command.contains(';') &&
      command.split(';').every((part) => part.trim().startsWith('getprop '))) {
    return command
        .split(';')
        .map((part) => _shellOutput('shell:${part.trim()}'))
        .join();
  }
  const properties = {
    'ro.build.version.sdk': '36',
    'ro.build.version.release': '16',
    'ro.product.model': 'VirtualAndroid',
    'ro.product.name': 'connect_fixture',
    'ro.product.device': 'connect_fixture',
    'ro.product.manufacturer': 'Connect Fixture',
    'ro.serialno': 'connect-usb-fixture',
    'ro.boot.serialno': 'connect-usb-fixture',
    'ro.product.cpu.abi': 'x86_64',
    'ro.product.cpu.abilist': 'x86_64,x86',
  };
  if (command == 'getprop') {
    return properties.entries.map((e) => '[${e.key}]: [${e.value}]\n').join();
  }
  if (command.startsWith('getprop ')) {
    return '${properties[command.substring(8).trim()] ?? ''}\n';
  }
  if (command.startsWith('echo ')) {
    return '${_unquote(command.substring(5))}\n';
  }
  if (command.startsWith('printf ')) {
    return _unquote(command.substring(7))
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r');
  }
  if (command == 'id') {
    return 'uid=2000(shell) gid=2000(shell) groups=2000(shell)\n';
  }
  if (command == 'uname -m') return 'x86_64\n';
  return 'connect-usb-fixture: simulated ADB peer; unsupported command\n';
}

String _unquote(String value) {
  if (value.length > 1 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

Uint8List _operation(int operation, int status) {
  final bytes = Uint8List(8);
  final view = ByteData.sublistView(bytes);
  view.setUint16(0, 0x111);
  view.setUint16(2, operation);
  view.setUint32(4, status);
  return bytes;
}

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);
Uint8List _u32le(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

Uint8List _device() {
  final bytes = Uint8List(312);
  final path = ascii.encode('/sys/devices/platform/usbip-fixture/usb1/1-1');
  bytes.setRange(0, path.length, path);
  bytes.setRange(256, 259, ascii.encode('1-1'));
  final view = ByteData.sublistView(bytes);
  view.setUint32(288, 1);
  view.setUint32(292, 1);
  view.setUint32(296, 3); // USB_SPEED_HIGH
  view.setUint16(300, 0x18d1);
  view.setUint16(302, 0x4ee7);
  view.setUint16(304, 0x0100);
  bytes.setRange(306, 312, [0, 0, 0, 1, 1, 1]);
  return bytes;
}

Uint8List? _descriptor(int type, int index) {
  if (type == 1) {
    return Uint8List.fromList([
      18,
      1,
      0,
      2,
      0,
      0,
      0,
      64,
      0xd1,
      0x18,
      0xe7,
      0x4e,
      0,
      1,
      1,
      2,
      3,
      1,
    ]);
  }
  if (type == 2 || type == 7) {
    return Uint8List.fromList([
      9,
      type,
      32,
      0,
      1,
      1,
      0,
      0x80,
      250,
      9,
      4,
      0,
      0,
      2,
      0xff,
      0x42,
      1,
      0,
      7,
      5,
      0x81,
      2,
      0,
      2,
      0,
      7,
      5,
      1,
      2,
      0,
      2,
      0,
    ]);
  }
  if (type == 3) {
    if (index == 0) return Uint8List.fromList([4, 3, 9, 4]);
    final value = switch (index) {
      1 => 'Connect Fixture',
      2 => 'Virtual Android',
      3 => 'connect-usb-fixture',
      _ => null,
    };
    if (value == null) return null;
    return Uint8List.fromList([
      2 + value.length * 2,
      3,
      for (final unit in value.codeUnits) ...[unit & 255, unit >> 8],
    ]);
  }
  return null; // Device qualifier / BOS: STALL, supported by USB enumeration.
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    if (!{
          '--port',
          '--bind',
          '--target-host',
          '--target-port',
        }.contains(args[index]) ||
        index + 1 == args.length) {
      stderr.writeln(
        'usage: dart run usbip_server.dart --port 3240 [--bind 127.0.0.1] '
        '[--target-host 127.0.0.1 --target-port 5555]',
      );
      exitCode = 64;
      return;
    }
    options[args[index]] = args[index + 1];
  }
  final server = await UsbIpAdbServer.start(
    address: InternetAddress(options['--bind'] ?? '127.0.0.1'),
    port: int.parse(options['--port'] ?? '3240'),
    targetHost: options['--target-host'],
    targetPort: options['--target-port'] == null
        ? null
        : int.parse(options['--target-port']!),
    log: stdout.writeln,
  );
  stdout.writeln(
    'usbip listening port=${server.port} busid=${server.busId} '
    'mode=${server.simulated ? 'simulated' : 'adbd'}',
  );
  final finished = Completer<void>();
  late StreamSubscription<ProcessSignal> interrupt;
  late StreamSubscription<ProcessSignal> terminate;
  void stop(ProcessSignal _) {
    if (!finished.isCompleted) finished.complete();
  }

  interrupt = ProcessSignal.sigint.watch().listen(stop);
  terminate = ProcessSignal.sigterm.watch().listen(stop);
  await finished.future;
  await interrupt.cancel();
  await terminate.cancel();
  await server.close();
}
