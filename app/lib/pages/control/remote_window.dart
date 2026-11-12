import 'dart:async';

import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/widgets/remote_failure.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

import 'models/remote_window_close.dart';

export 'models/remote_window_close.dart';

/// 单个路由窗口拥有设备音源租约、手机控制页计数和精确会话视图。
/// 输入排空、可见性切换与关闭均在这里排序，页面只负责呈现和导航反馈。
class RemoteWindow {
  RemoteWindow({
    required this.control,
    required this.videos,
    required this.inspection,
    required this.apps,
    required this.connectionId,
    required this._lockOnClose,
    required this._current,
    required this.deviceId,
    required this.views,
  }) {
    _releaseDeviceView = views.claimRemoteDeviceView(deviceId);
  }

  final RemoteControl control;
  final VideoSessions videos;
  final DeviceInspection inspection;
  final DeviceApps apps;
  final String? Function() connectionId;
  final bool Function() _lockOnClose;
  final bool Function() _current;
  final RemoteViews views;
  final String deviceId;
  final presentation = RemotePresentation();
  late final void Function() _releaseDeviceView;
  bool Function()? _releaseControlPage;
  SessionViewLease? _view;
  bool _disposed = false;
  Future<void>? _disposing;
  bool get isCurrent => !_disposed && _current();
  SessionViewLease? get view => _view;

  void bind({required bool visible}) {
    if (!isCurrent) throw StateError('画面所有者已释放。');
    _releaseControlPage?.call();
    _releaseControlPage = views.claimControlPage(
      deviceId,
      sessionId: presentation.sessionId,
    );
    _view = views.claimSessionViewLease(
      presentation.sessionId,
      visible: visible,
    );
  }

  void abandonEndedSession() {
    _view?.abandonEndedSession();
    _view = null;
  }

  void detachUnknownLaunch(Json record, Future<void> Function() releaseInputs) {
    final outgoing = presentation.permitDetachedCleanup();
    final releases = releaseInputs().whenComplete(() {
      presentation.finishDetachedCleanup(outgoing);
    });
    final owned = _view;
    _view = null;
    presentation.detachBinding();
    if (owned != null) {
      unawaited(
        owned.release(afterInput: releases).catchError((Object _) => null),
      );
    }
    // 操作记录的检查不依赖旧输入或捕获暂停的回执。
    presentation.showUnknownAppLaunch(record);
  }

  Future<String?> convertToIndependent({
    required bool Function() canSendInput,
    required Future<void> Function() releaseInputs,
  }) async {
    if (!isCurrent) return null;
    final binding = presentation.binding;
    final owned = view;
    final id = deviceId;
    final connection = connectionId();
    if (connection == null || connection.isEmpty) {
      throw const RequestFailure('stale_connection', '尚未确认当前设备连接。');
    }
    bool current() =>
        isCurrent &&
        !presentation.exiting &&
        canSendInput() &&
        presentation.binding == binding &&
        view == owned &&
        connectionId() == connection;
    final foreground = await inspection.readForegroundApp(
      id,
      connectionId: connection,
    );
    if (!current()) return null;
    final package = foreground.value;
    if (foreground.deviceId != id ||
        foreground.connectionId != connection ||
        package.isEmpty) {
      throw const RequestFailure('foreground_unavailable', '无法确认手机当前前台应用。');
    }
    final running = await apps.readRunningApps(id);
    if (!current()) return null;
    if (running.deviceId != id ||
        (running.connectionId != null && running.connectionId != connection) ||
        !running.apps.any((app) => app.packageName == package)) {
      throw const RequestFailure('foreground_unavailable', '当前前台内容没有可接续的应用任务。');
    }
    final verified = await inspection.readForegroundApp(
      id,
      connectionId: connection,
    );
    if (!current()) return null;
    if (verified.value != package ||
        verified.connectionId != connection ||
        verified.deviceId != id) {
      throw const RequestFailure('foreground_unavailable', '手机前台应用已变化，请重试。');
    }
    await owned!.close(afterInput: releaseInputs());
    if (!isCurrent ||
        presentation.exiting ||
        presentation.binding != binding ||
        connectionId() != connection) {
      return null;
    }
    presentation.detachBinding();
    return package;
  }

  Future<void> pause(Future<void> Function() releaseInputs) async {
    if (presentation.exiting || presentation.appLaunchUnknown) return;
    final owned = _view;
    if (owned == null || !owned.isCurrent) return;
    // 必须先撤销输入许可，再开始排空旧绑定。
    final epoch = presentation.beginPause();
    try {
      await owned.pause(afterInput: releaseInputs());
    } catch (failure) {
      if (!_disposed && presentation.acceptsVisibilityFailure(epoch)) {
        presentation.reportError(remoteFailure(failure));
      }
    }
  }

  Future<RemoteResumeResult> resume({
    required bool foreground,
    required Future<void> afterInput,
  }) async {
    if (!isCurrent || !presentation.canResume(foreground: foreground)) {
      return RemoteResumeResult.stale;
    }
    var owned = _view;
    if (owned == null || !owned.isCurrent) {
      owned = views.claimSessionViewLease(
        presentation.sessionId,
        visible: false,
      );
      _view = owned;
      _releaseControlPage?.call();
      _releaseControlPage = null;
    }
    _releaseControlPage ??= views.claimControlPage(
      deviceId,
      sessionId: presentation.sessionId,
    );
    final epoch = presentation.beginResume();
    try {
      final receipt = await owned.resume(afterInput: afterInput);
      if (!isCurrent) return RemoteResumeResult.stale;
      final outcome = presentation.completeResume(
        epoch,
        receipt?.toSnapshot() ?? const {},
        ownerCurrent: owned.isCurrent,
      );
      if (outcome == RemoteResumeResult.rendererNotReady) {
        throw const RequestFailure('renderer_not_ready', '尚未确认恢复后的画面，请重新检查。');
      }
      return outcome;
    } catch (failure) {
      if (!_disposed && presentation.acceptsVisibilityFailure(epoch)) {
        presentation.failOperation(remoteFailure(failure));
      }
      return RemoteResumeResult.stale;
    }
  }

  Future<RemoteWindowClose> close(Future<void> Function() releaseInputs) async {
    _releaseDeviceView();
    presentation.leave();
    final owned = _view;
    final id = presentation.sessionId;
    final captureGeneration = presentation.session?['captureGeneration'];
    final lock =
        owned?.isCurrent == true &&
        presentation.controlAvailable &&
        !presentation.stateUnverified &&
        isCurrent &&
        _lockOnClose();
    final lastPage = _releaseControlPage?.call() == true;
    _releaseControlPage = null;
    Object? lockFailure;
    try {
      if (id.isNotEmpty && owned?.ownsBinding == true) {
        final releases = releaseInputs();
        presentation.revokeControl();
        await releases;
        if (lock &&
            isCurrent &&
            lastPage &&
            !views.hasControlPages(deviceId) &&
            owned!.ownsBinding) {
          try {
            for (final action in [ControlKeyAction.down, ControlKeyAction.up]) {
              await control.sendControl(
                ControlTarget(
                  sessionId: id,
                  captureGeneration: captureGeneration is int
                      ? captureGeneration
                      : null,
                ),
                ControlAction.key(223, action: action),
              );
            }
          } catch (failure) {
            lockFailure = failure;
          }
        }
        if (owned!.ownsBinding) {
          return RemoteWindowClose(
            receipt: await owned.close(),
            lockFailure: lockFailure,
          );
        }
      } else if (id.isNotEmpty && owned == null && !presentation.sessionEnded) {
        // 没有首帧也可能已经取得远端身份，明确关闭仍只释放该身份。
        return RemoteWindowClose(
          receipt: await videos.stopVideo(ControlTarget(sessionId: id)),
        );
      }
      return RemoteWindowClose(lockFailure: lockFailure);
    } catch (failure) {
      return RemoteWindowClose(lockFailure: lockFailure, closeFailure: failure);
    }
  }

  Future<void> dispose(Future<void> Function() releaseInputs) =>
      _disposing ??= _dispose(releaseInputs);

  Future<void> _dispose(Future<void> Function() releaseInputs) async {
    _disposed = true;
    _releaseControlPage?.call();
    _releaseControlPage = null;
    _releaseDeviceView();
    presentation.invalidateStart();
    final release = releaseInputs();
    final owned = _view;
    if (!presentation.exiting && owned != null) {
      await owned.close(afterInput: release).catchError((Object _) => null);
    }
    await release;
  }
}
