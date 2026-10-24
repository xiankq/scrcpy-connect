import 'dart:async';

import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/presentation/remote_failure.dart';
import 'package:scrcpy_connect/media/session_view_registry.dart';

import 'remote_presentation.dart';

class RemoteWindowClose {
  const RemoteWindowClose({
    this.receipt = const {},
    this.lockFailure,
    this.closeFailure,
  });
  final Json receipt;
  final Object? lockFailure;
  final Object? closeFailure;
}

/// 单个路由窗口拥有设备音源租约、手机控制页计数和精确会话视图。
/// 输入排空、可见性切换与关闭均在这里排序，页面只负责呈现和导航反馈。
class RemoteWindow {
  RemoteWindow({required this.controller, required this.deviceId}) {
    _releaseDeviceView = controller.claimRemoteDeviceView(deviceId);
  }

  final AppController controller;
  final String deviceId;
  final presentation = RemotePresentation();
  late final void Function() _releaseDeviceView;
  bool Function()? _releaseControlPage;
  SessionViewLease? _view;
  bool _disposed = false;
  SessionViewLease? get view => _view;

  void bind({required bool visible}) {
    _releaseControlPage?.call();
    _releaseControlPage = controller.claimControlPage(
      deviceId,
      sessionId: presentation.sessionId,
    );
    _view = controller.claimSessionViewLease(
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
        owned
            .release(afterInput: releases)
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
    // 操作记录的检查不依赖旧输入或捕获暂停的回执。
    presentation.showUnknownAppLaunch(record);
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
    if (!presentation.canResume(foreground: foreground)) {
      return RemoteResumeResult.stale;
    }
    var owned = _view;
    if (owned == null || !owned.isCurrent) {
      owned = controller.claimSessionViewLease(
        presentation.sessionId,
        visible: false,
      );
      _view = owned;
      _releaseControlPage?.call();
      _releaseControlPage = null;
    }
    _releaseControlPage ??= controller.claimControlPage(
      deviceId,
      sessionId: presentation.sessionId,
    );
    final epoch = presentation.beginResume();
    try {
      final receipt = await owned.resume(afterInput: afterInput);
      if (_disposed) return RemoteResumeResult.stale;
      final outcome = presentation.completeResume(
        epoch,
        receipt,
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
        jsonObject(
              jsonObject(
                controller.snapshot().settings['deviceSettings'],
              )[deviceId],
            )['lockOnClose'] ==
            true;
    final lastPage = _releaseControlPage?.call() == true;
    _releaseControlPage = null;
    Object? lockFailure;
    try {
      if (id.isNotEmpty && owned?.ownsBinding == true) {
        final releases = releaseInputs();
        presentation.revokeControl();
        await releases;
        if (lock &&
            lastPage &&
            !controller.hasControlPages(deviceId) &&
            owned!.ownsBinding) {
          try {
            for (final action in ['down', 'up']) {
              await controller.execute(ApplicationCommand.sessionKey, {
                'sessionId': id,
                if (captureGeneration is int)
                  'captureGeneration': captureGeneration,
                'keyCode': 223,
                'action': action,
              });
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
          receipt: await controller.execute(ApplicationCommand.sessionStop, {
            'sessionId': id,
            'keepTask': true,
          }),
        );
      }
      return RemoteWindowClose(lockFailure: lockFailure);
    } catch (failure) {
      return RemoteWindowClose(lockFailure: lockFailure, closeFailure: failure);
    }
  }

  Future<void> dispose(Future<void> Function() releaseInputs) {
    _disposed = true;
    _releaseControlPage?.call();
    _releaseControlPage = null;
    _releaseDeviceView();
    presentation.invalidateStart();
    final release = releaseInputs();
    final owned = _view;
    if (!presentation.exiting && owned != null) {
      unawaited(
        owned
            .close(afterInput: release)
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
    return release;
  }
}
