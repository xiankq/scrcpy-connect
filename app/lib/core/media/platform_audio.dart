import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/audio_platform.dart';

/// Android 系统音频协议适配；应用内只交付已解析的平台事实。
final class PlatformAudio implements AudioPlatform {
  PlatformAudio({required this._request});
  final Future<Json> Function(String, Json) _request;
  Future<Json> _call(String command, Json params) async {
    try {
      return await _request(command, params);
    } on PlatformException catch (error) {
      throw RequestFailure(error.code, error.message ?? '系统声音操作未完成。');
    }
  }

  @override
  Future<AudioFocusResult> acquireFocus(String ownerId) async {
    final result = await _call('audio.platform.focus.acquire', {
      'ownerId': ownerId,
    });
    return AudioFocusResult(
      granted: result['granted'] == true,
      epoch: result['epoch'] is int ? result['epoch'] as int : null,
    );
  }

  @override
  Future<bool> releaseFocus(String ownerId, int epoch) async =>
      (await _call('audio.platform.focus.release', {
        'ownerId': ownerId,
        'epoch': epoch,
      }))['released'] ==
      true;

  @override
  Future<AudioBackgroundState> setBackground(
    String ownerId,
    bool enabled,
  ) async {
    final result = await _call('audio.platform.background', {
      'ownerId': ownerId,
      'enabled': enabled,
    });
    return AudioBackgroundState(
      ready: result['ready'] == true || result['mediaPlaybackReady'] == true,
      supported: result['supported'] != false,
    );
  }

  Future<bool> readVisible() async =>
      (await _call('audio.platform.state', const {}))['visible'] == true;
}

/// 原生通道在此结束；未知或不完整消息没有可交付的平台事实。
AudioPlatformEvent? decodeAudioPlatformEvent(Map<String, dynamic> event) {
  final raw = event['data'];
  final data = raw is Map ? raw : event;
  return switch (event['type']) {
    'audio.platform.visibility' when data['visible'] is bool =>
      AudioVisibilityChanged(data['visible'] as bool),
    'audio.platform.background'
        when data['ownerId'] is String && data['ready'] is bool =>
      AudioBackgroundChanged(
        ownerId: data['ownerId'] as String,
        ready: data['ready'] as bool,
      ),
    'audio.platform.focus'
        when data['epoch'] is int && (data['epoch'] as int) >= 0 =>
      switch (data['signal']) {
        'granted' => AudioFocusChanged(
          epoch: data['epoch'] as int,
          signal: .granted,
        ),
        'transientLoss' => AudioFocusChanged(
          epoch: data['epoch'] as int,
          signal: .transientLoss,
        ),
        'permanentLoss' => AudioFocusChanged(
          epoch: data['epoch'] as int,
          signal: .permanentLoss,
        ),
        'noisy' => AudioFocusChanged(
          epoch: data['epoch'] as int,
          signal: .noisy,
        ),
        _ => null,
      },
    _ => null,
  };
}
