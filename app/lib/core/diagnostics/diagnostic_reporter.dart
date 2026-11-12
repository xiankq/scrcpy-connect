import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

class DiagnosticReporter {
  DiagnosticReporter(this.log);
  final DiagnosticLog? log;
  final _presentations = <String, (int?, String)>{};
  static final _component = RegExp(r'^(?:c2\.|OMX\.)[a-zA-Z0-9_.-]{1,76}$');

  // 仅限制日志中的操作标识，不参与业务准入或分发。
  static const _operations = {
    'activities.list',
    'activities.stop',
    'session.display',
    'session.list',
    'session.pause',
    'session.quality',
    'session.quality.options',
    'session.reconfigure',
    'session.resume',
    'session.screenshot',
    'session.start',
    'session.stop',
    'state.reconcile',
    'audio.sources',
    'audio.eligibility',
    'audio.start',
    'audio.stop',
    'audio.pause',
    'audio.resume',
    'audio.volume',
  };
  static const _important = {
    'devices.connect',
    'devices.pair',
    'devices.pair.qr',
    'devices.usb',
    'devices.wireless',
    'session.start',
    'session.stop',
    'session.pause',
    'session.resume',
    'session.quality',
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
    if (log == null || !_operations.contains(command)) return;
    // 指针、触摸和周期状态流量不能挤占日志容量。
    if (error == null && !_important.contains(command)) return;
    final device = params['deviceId'];
    _request(
      command,
      device is String ? device : null,
      elapsedMs,
      error: error,
    );
  }

  /// 诊断标识不参与业务分发；类型化剪贴板入口只交付关联身份与机器失败。
  void clipboardFailure(
    String deviceId,
    bool writing,
    int elapsedMs,
    Object error,
  ) => _request(
    writing ? 'clipboard.set' : 'clipboard.get',
    deviceId,
    elapsedMs,
    error: error,
  );

  void controlFailed(
    ControlTarget target,
    ControlAction action,
    Object error,
    int elapsedMs,
  ) => _request(
    switch (action) {
      ControlKey() => 'session.key',
      ControlTouch() => 'session.touch',
      ControlText() => 'session.text',
      ControlScroll() => 'session.scroll',
      ControlRotate() => 'session.rotate',
      ControlScreenPower() => 'session.screen',
      ControlLaunchApplication() => 'session.launch',
    },
    target.deviceId,
    elapsedMs,
    error: error,
  );

  /// 标识只用于诊断，不参与观察操作的选择或分派。
  void observationFailed(
    String label,
    String? deviceId,
    Object error,
    int elapsedMs,
  ) => _request(label, deviceId, elapsedMs, error: error);

  void fileOperationFailed(
    String operation,
    String? deviceId,
    Object error,
    int elapsedMs,
  ) => _request(operation, deviceId, elapsedMs, error: error);

  void appCatalogFailed(
    String label,
    String deviceId,
    Object error,
    int elapsedMs,
  ) => _request(label, deviceId, elapsedMs, error: error);

  void deviceSetup(
    String label,
    String? deviceId,
    int elapsedMs, {
    Object? error,
  }) => _request(label, deviceId, elapsedMs, error: error);

  void deviceWakeFailed(String id, Object error, int elapsedMs) =>
      _request('devices.wake', id, elapsedMs, error: error);

  void deviceRecordFailed(String? id, Object error, int elapsedMs) =>
      _request('devices.add', id, elapsedMs, error: error);

  void deviceConnected(String id, int elapsedMs) =>
      _request('devices.connect', id, elapsedMs);

  void deviceConnectionFailed(
    String id, {
    required bool configuring,
    required int elapsedMs,
    required Object error,
  }) => _request(
    configuring ? 'devices.configure' : 'devices.connect',
    id,
    elapsedMs,
    error: error,
  );

  void deviceStopped(
    String deviceId, {
    required bool forgotten,
    required int elapsedMs,
    Object? error,
  }) => _request(
    forgotten ? 'devices.forget' : 'devices.disconnect',
    deviceId,
    elapsedMs,
    error: error,
  );

  void deviceCancellationFailed(Object error, int elapsedMs) =>
      _request('devices.cancel', null, elapsedMs, error: error);

  void _request(
    String command,
    String? deviceId,
    int elapsedMs, {
    Object? error,
  }) {
    if (log == null) return;
    if (error is RequestFailure && error.code == 'cancelled') {
      return;
    }
    log!.record(
      DiagnosticArea.runtime,
      error == null ? 'request.completed' : 'request.failed',
      level: error == null ? LogLevel.info : LogLevel.error,
      fields: {
        'command': command,
        'elapsedMs': elapsedMs,
        if (deviceId != null) 'scope': log!.scope(deviceId),
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error is RequestFailure) 'code': error.code,
      },
    );
  }

  void applicationEvent(Map<String, dynamic> event) {
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
    // 只记录生命周期变化，不记录通知、剪贴板或文件内容。
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
        if (type == 'session.disconnected' &&
            data['sessionId'] is String &&
            log != null)
          'sessionScope': log!.scope(data['sessionId'] as String),
        if (type == 'session.disconnected' &&
            const {
              'control_closed',
              'control_read_failed',
              'control_write_failed',
              'control_write_timeout',
              'control_protocol_error',
              'server_process_closed',
              'server_process_read_failed',
              'video_read_failed',
              'media_decoder',
              'media_stall',
              'media_protocol',
              'media_ended',
              'media_detached',
              'renderer_timeout',
              'video_timeout',
              'video_protocol',
              'video_renderer_timeout',
              'media_source_closed',
            }.contains(data['failureCode']))
          'code': data['failureCode'],
        if (type == 'session.disconnected' &&
            const {
              'control_read',
              'control_write',
              'control_protocol',
              'server_process',
              'video_read',
              'video_output',
            }.contains(data['failureStage']))
          'stage': data['failureStage'],
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
      const codecNames = {
        'h264',
        'hevc',
        'av1',
        'vp8',
        'vp9',
        'libdav1d',
        'pcm_s16le',
        'h264_mediacodec',
        'hevc_mediacodec',
        'av1_mediacodec',
        'vp8_mediacodec',
        'vp9_mediacodec',
      };
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
      final nativeName = event['decoderName'];
      final parts = nativeName is String && nativeName.length <= 256
          ? nativeName.split('/')
          : const <String>[];
      final decoder = parts.isNotEmpty && codecNames.contains(parts.first)
          ? parts.first
          : known.contains(event['detail'])
          ? event['detail']
          : 'unknown';
      final backend =
          parts.length >= 2 &&
              const {
                'mediacodec',
                'vaapi',
                'd3d11va',
                'dxva2',
                'cuda',
                'videotoolbox',
              }.contains(parts[1])
          ? parts[1]
          : null;
      final component =
          backend == 'mediacodec' &&
              parts.length == 3 &&
              _component.hasMatch(parts[2])
          ? parts[2]
          : null;
      final failed = error is num && error < 0;
      final verification = event['hardwareVerification'];
      final verified = event['runtimeSelectionVerified'] == true;
      // MediaCodec 软件组件也可能输出不透明帧；官方组件分类优先于帧格式。
      final acceleration =
          verified &&
              verification == 'hardware' &&
              event['hardwareAccelerated'] == true
          ? 'hardware'
          : decoder == 'pcm_s16le' ||
                (verified && verification == 'software') ||
                (verification == null &&
                    (decoder == 'FFmpeg' ||
                        decoder == 'dav1d' ||
                        decoder == 'libdav1d' ||
                        decoder == 'pcm_s16le' ||
                        event['hardwareAccelerated'] == false))
          ? 'software'
          : 'unknown';
      log!.record(
        area,
        failed ? 'decoder.failed' : 'decoder.selected',
        level: failed ? LogLevel.warning : LogLevel.info,
        fields: {
          'scope': log!.scope(id),
          'generation': ?generation,
          'decoder': decoder,
          'decoderBackend': ?backend,
          'decoderComponent': ?component,
          // 平台接口名称本身不能证明物理硬件加速。
          'acceleration': acceleration,
          if (event['backendHardwareFrames'] is bool)
            'backendHardwareFrames': event['backendHardwareFrames'],
          if (error is num) 'nativeError': error,
        },
      );
    } else if (event['kind'] == 'failed') {
      log!.record(
        area,
        'playback.failed',
        level: LogLevel.error,
        fields: {
          'scope': log!.scope(id),
          'generation': ?generation,
          if (const {
            'decoder_error',
            'presentation_error',
            'media_source_ended',
            'native_status_error',
          }.contains(event['code']))
            'code': event['code'],
          if (const {
            'video_decode',
            'video_presentation',
            'audio_output',
            'status_poll',
          }.contains(event['stage']))
            'stage': event['stage'],
          if (event['nativeError'] is int) 'nativeError': event['nativeError'],
        },
      );
    } else if (category == 'video.presentation') {
      const paths = {
        'vaapi/egl',
        'cuda/gl',
        'yuv/gl',
        'readback/gl',
        'cpu/gl',
        'd3d11va/dxgi',
        'readback/dxgi',
        'cpu/dxgi',
        'cpu/d3d11',
        'apple-videotoolbox',
        'apple-software-bgra',
        'apple-texture',
        'android-mediacodec-surface',
        'android-software-window',
        'android-jni',
      };
      final raw = event['presentationPath'];
      final path = raw is String && paths.contains(raw)
          ? raw.replaceAll('/', '.')
          : 'unknown';
      final state = (generation, path);
      if (_presentations[id] == state) return;
      // 状态采样可能逐帧发布；持久日志只记录首次准备和路径、代际变化。
      _presentations.remove(id);
      _presentations[id] = state;
      if (_presentations.length > 64) {
        _presentations.remove(_presentations.keys.first);
      }
      log!.record(
        area,
        'video.presentation',
        fields: {
          'scope': log!.scope(id),
          'generation': ?generation,
          'presentationPath': path,
          if (event['presentedSequence'] is int)
            'presentedSequence': event['presentedSequence'],
          'platformTexturePrepared': event['platformTexturePrepared'] == true,
          // 此回调只证明平台准备完成，不证明最终屏幕显示。
          'presentedToWidget': false,
        },
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

  void failure(DiagnosticArea area, String id, Object error, {String? stage}) {
    log?.record(
      area,
      'playback.failed',
      level: LogLevel.error,
      fields: {
        if (log != null) 'scope': log!.scope(id),
        'errorType': error.runtimeType.toString(),
        if (error is RequestFailure) 'code': error.code,
        if (const {'video_open'}.contains(stage)) 'stage': stage,
      },
    );
  }

  void release(DiagnosticArea area, String id, Map<String, dynamic> receipt) {
    _presentations.remove(id);
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
