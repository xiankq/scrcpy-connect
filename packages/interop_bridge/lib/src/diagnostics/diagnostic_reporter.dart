import '../interop_exception.dart';
import '../protocol/commands_generated.dart';
import 'diagnostic_log.dart';

class DiagnosticReporter {
  const DiagnosticReporter(this.log);
  final DiagnosticLog? log;

  static final _commands = InteropCommand.values.map((c) => c.wire).toSet();
  static const _important = {
    'devices.connect',
    'devices.disconnect',
    'adb.pair',
    'devices.forget',
    'session.start',
    'session.stop',
    'session.pause',
    'session.resume',
    'session.quality',
    'apps.launch',
    'audio.start',
    'audio.stop',
    'documents.send',
    'transfers.cancel',
  };

  void command(
    String command,
    Map<String, dynamic> params,
    int elapsedMs, {
    Object? error,
  }) {
    if (log == null || !_commands.contains(command)) return;
    // Pointer, touch and periodic status traffic must not overwhelm the log.
    if (error == null && !_important.contains(command)) return;
    if (error is InteropException && error.code == 'cancelled') return;
    log!.record(
      DiagnosticArea.runtime,
      error == null ? 'request.completed' : 'request.failed',
      level: error == null ? LogLevel.info : LogLevel.error,
      fields: {
        'command': command,
        'elapsedMs': elapsedMs,
        if (params['deviceId'] is String)
          'scope': log!.scope(params['deviceId'] as String),
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error is InteropException) 'code': error.code,
      },
    );
  }

  void coreEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (!const {
      'device.changed',
      'session.disconnected',
      'audio.updated',
      'platform.failed',
      'connections.stopped',
    }.contains(type)) {
      return;
    }
    final data = event['data'] is Map
        ? Map<Object?, Object?>.from(event['data'] as Map)
        : const <Object?, Object?>{};
    // Only lifecycle changes, never notification, clipboard or file content.
    if (type == 'audio.updated' &&
        !const {'failed', 'stopped', 'error'}.contains(data['status'])) {
      return;
    }
    log?.record(
      type == 'device.changed'
          ? DiagnosticArea.connection
          : DiagnosticArea.runtime,
      type as String,
      level: type == 'platform.failed' || data['status'] == 'failed'
          ? LogLevel.error
          : LogLevel.info,
      fields: {
        if (event['deviceId'] is String && log != null)
          'scope': log!.scope(event['deviceId'] as String),
        if (const {
          'connected',
          'connecting',
          'offline',
          'unauthorized',
          'failed',
          'stopped',
          'error',
        }.contains(data['status']))
          'status': data['status'],
      },
    );
  }

  void playerEvent(
    DiagnosticArea area,
    String id,
    Map<String, dynamic> event, {
    int? generation,
  }) {
    if (log == null) return;
    final category = event['category'];
    final error = event['error'];
    if (category == 'decoder.video' || category == 'decoder.audio') {
      const known = {
        'AMediaCodec',
        'VT',
        'MFT',
        'D3D11',
        'DXVA',
        'VAAPI',
        'FFmpeg',
        'dav1d',
        'CUDA',
        'NVDEC',
      };
      final decoder = known.contains(event['detail'])
          ? event['detail']
          : 'unknown';
      final failed = error is num && error < 0;
      final software = decoder == 'FFmpeg' || decoder == 'dav1d';
      log!.record(
        area,
        failed ? 'decoder.failed' : 'decoder.selected',
        level: failed ? LogLevel.warning : LogLevel.info,
        fields: {
          'scope': log!.scope(id),
          'generation': ?generation,
          'decoder': decoder,
          // A platform API name alone never establishes physical acceleration.
          'acceleration': software ? 'software' : 'unknown',
          if (error is num) 'nativeError': error,
        },
      );
    } else if (event['kind'] == 'failed') {
      log!.record(
        area,
        'playback.failed',
        level: LogLevel.error,
        fields: {'scope': log!.scope(id), 'generation': ?generation},
      );
    } else if (category == 'video.prepare' || category == 'video.texture') {
      log!.record(
        area,
        category as String,
        fields: {
          'scope': log!.scope(id),
          'elapsedMs': event['elapsedMs'],
          'generation': ?generation,
        },
      );
    }
  }

  void failure(DiagnosticArea area, String id, Object error) {
    log?.record(
      area,
      'playback.failed',
      level: LogLevel.error,
      fields: {
        if (log != null) 'scope': log!.scope(id),
        'errorType': error.runtimeType.toString(),
        if (error is InteropException) 'code': error.code,
      },
    );
  }

  void release(DiagnosticArea area, String id, Map<String, dynamic> receipt) {
    log?.record(
      area,
      'output.released',
      level:
          receipt['disposeDeferred'] == true ||
              receipt['cleanupUnconfirmed'] == true
          ? LogLevel.warning
          : LogLevel.info,
      fields: {...receipt, if (log != null) 'scope': log!.scope(id)},
    );
  }
}
