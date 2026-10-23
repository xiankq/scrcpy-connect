import 'dart:async';

import 'package:device_protocol/device_protocol.dart';

typedef IntakeRequest = Future<Map<String, dynamic>> Function(
  String command,
  Map<String, dynamic> params,
);

/// Attaches OS-granted URI handles to the shared Rust importer. It never copies
/// content, owns a task journal, or decides when a transfer source can be deleted.
class ShareIntake {
  ShareIntake({
    required this._core,
    required this._platform,
    required this._isDisposed,
  });

  final IntakeRequest _core;
  final IntakeRequest _platform;
  final bool Function() _isDisposed;
  final _pending = <String, Future<void>>{};
  final _opening = <String>{};
  Future<void>? _configuration;
  int _serial = 0;

  Future<void> configure() => _configuration ??= _configure();

  Future<void> _configure() async {
    final environment = await _platform(
      'sharing.platform.environment',
      const {},
    );
    final cache = environment['cacheDirectory'];
    if (cache is! String || cache.isEmpty) {
      throw const InteropException('cache_unavailable', '系统未提供应用暂存目录。');
    }
    await _core('sharing.configure', {
      'allowedCacheRoot': cache,
      'absoluteRoot': '$cache/incoming',
    });
  }

  Future<void> attach() async {
    await configure();
    final response = await _platform('sharing.platform.pending', const {});
    for (final raw in (response['shares'] as List<Object?>? ?? const [])) {
      if (raw is Map<Object?, Object?>) {
        await receive(Map<String, dynamic>.from(raw));
      }
    }
  }

  Future<void> receive(Map<String, dynamic> share) {
    final id = share['shareId'];
    if (id is! String || _isDisposed()) return Future<void>.value();
    final existing = _pending[id];
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _receive(share, id).whenComplete(() {
      if (identical(_pending[id], operation)) _pending.remove(id);
    });
    _pending[id] = operation;
    return operation;
  }

  Future<void> _receive(Map<String, dynamic> share, String id) async {
    final opened = <Map<String, dynamic>>[];
    try {
      await configure();
      if (_isDisposed()) return;
      if (share['status'] == 'error') {
        await _core('sharing.reject', {
          'shareId': id,
          'reason': (share['errors'] as List<Object?>? ?? const []).join('；'),
        });
      } else {
        final count = share['sourceCount'];
        if (count is! int || count < 0 || count > 32) {
          throw const InteropException('invalid_share', '系统分享文件数量无效。');
        }
        for (var index = 0; index < count; index++) {
          final openId = '$id:${_serial++}';
          _opening.add(openId);
          try {
            opened.add(
              await _platform('sharing.platform.open', {
                'shareId': id,
                'index': index,
                'openId': openId,
              }).timeout(const Duration(seconds: 120)),
            );
          } on TimeoutException {
            await _platform('sharing.platform.cancel', {'openId': openId});
            rethrow;
          } finally {
            _opening.remove(openId);
          }
          if (_isDisposed()) return;
        }
        // The acknowledgement means Rust has duplicated every descriptor and
        // owns the import job. Native originals can be closed immediately.
        await _core('sharing.import', {
          'shareId': id,
          'text': share['text'],
          'mime': share['mime'],
          'sources': [
            for (final source in opened)
              {
                'name': source['name'],
                'fd': source['fd'],
                'offset': source['offset'],
                'declaredLength': source['declaredLength'],
              },
          ],
        });
      }
      await _platform('sharing.platform.consume', {'shareId': id});
    } catch (error) {
      if (!_isDisposed()) {
        await _core('sharing.reject', {'shareId': id, 'reason': '$error'});
        await _platform('sharing.platform.consume', {'shareId': id});
      }
    } finally {
      Object? releaseError;
      StackTrace? releaseStack;
      for (final source in opened) {
        try {
          await _platform('sharing.platform.release', {
            'fdLeaseId': source['fdLeaseId'],
          });
        } catch (error, stack) {
          releaseError ??= error;
          releaseStack ??= stack;
        }
      }
      if (releaseError != null) {
        Error.throwWithStackTrace(releaseError, releaseStack!);
      }
    }
  }

  Future<void> detach() async {
    for (final id in _opening.toList()) {
      await _platform('sharing.platform.cancel', {'openId': id});
    }
  }
}
