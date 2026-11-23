import 'dart:async';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_playback_resumed.dart';
import 'package:scrcpy_connect/core/media/models/video_session_changed.dart';

import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/widgets/remote_failure.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:scrcpy_connect/core/control/models/app_launch_record.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';

import 'models/remote_window_close.dart';
import 'models/remote_video_update.dart';

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
  _RemoteOpening? _opening;
  bool get isCurrent => !_disposed && _current();
  SessionViewLease? get view => _view;
  bool get recoveringConnection => _opening?.recoveringConnection == true;

  /// 异设备、异会话、旧捕获及核验中的回执不能改变窗口或触发视图工作。
  /// 返回值只描述 Widget 需要执行的工作，不转移输入和布局的所有权。
  RemoteVideoUpdate? acceptVideoEvent(RuntimeEvent event) {
    if (!isCurrent ||
        presentation.appLaunchUnknown ||
        presentation.stateUnverified ||
        (presentation.reconcileOnly && view?.isCurrent != true)) {
      return null;
    }
    bool belongs(String id, String device) =>
        id == presentation.sessionId &&
        device == deviceId &&
        (event.deviceId == null || event.deviceId == device);
    final payload = event.data;
    switch (payload) {
      case VideoOutputReady(:final output) ||
          VideoOutputChanged(:final output) ||
          VideoOutputFrame(:final output):
        if (!belongs(output.sessionId, output.deviceId) ||
            !presentation.output(
              output,
              verified: payload is! VideoOutputFrame,
            )) {
          return null;
        }
        return const RemoteVideoUpdate(geometryChanged: true);
      case VideoPlaybackResumed(
        receipt: VideoPlaybackReceipt(:final session, :final output),
      ):
        if (!belongs(session.sessionId, session.deviceId) ||
            !presentation.output(output, verified: true)) {
          return null;
        }
        return const RemoteVideoUpdate(geometryChanged: true);
      case VideoOutputFailed(
        :final sessionId,
        :final deviceId,
        :final captureGeneration,
        :final generation,
        :final reason,
      ):
        if (!belongs(sessionId, deviceId) ||
            !presentation.acceptsFailure(
              captureGeneration: captureGeneration,
              generation: generation,
            )) {
          return null;
        }
        presentation.disconnect(reason);
        return const RemoteVideoUpdate(releaseInputs: true);
      case VideoSessionChanged(view: final sessionView):
        final session = sessionView.session;
        if (event.telemetry || !belongs(session.sessionId, session.deviceId)) {
          return null;
        }
        final outgoing = presentation.binding;
        final noticeIsCurrent =
            view?.isCurrent == true &&
            presentation.acceptsFailure(
              captureGeneration: session.captureGeneration,
              generation: session.generation,
            );
        var releaseInputs = false;
        RemoteBinding? previousBinding;
        if (!session.live) {
          if (!noticeIsCurrent) return null;
          presentation.updateSession(sessionView);
          presentation.disconnect(
            failureCodeMessage(
              session.failureCode,
              fallback:
                  presentation.error ??
                  (session.status == .stopped
                      ? '手机画面已关闭。需要时可重新打开。'
                      : '手机画面已断开。请检查手机连接后重试。'),
            ),
          );
          releaseInputs = true;
          previousBinding = outgoing;
        } else if (presentation.updateSession(sessionView)) {
          releaseInputs = true;
          previousBinding = outgoing != presentation.binding ? outgoing : null;
        }
        return RemoteVideoUpdate(
          releaseInputs: releaseInputs,
          previousBinding: previousBinding,
          wake: noticeIsCurrent ? sessionView.wake : null,
        );
      default:
        return const RemoteVideoUpdate(changed: false);
    }
  }

  /// 选择既有会话或提交一次打开；迟到回执仍由借用原能力的窗口清理。
  /// 页面提供尺寸及明确唤醒的准备工作，不参与会话选择或回执归属判断。
  Future<RemoteWindowOpened?> open({
    required String? packageName,
    required bool recoveringConnection,
    required Future<void> Function() releaseInputs,
    required Future<VideoSessionPlan?> Function(bool Function() current)
    prepare,
    required bool Function() canProceed,
    VideoSessionView? existing,
  }) async {
    if (!isCurrent || presentation.exiting) return null;
    if (presentation.appLaunchUnknown) {
      await checkAppLaunch(packageName);
      return null;
    }
    if (presentation.stateUnverified ||
        (presentation.reconcileOnly && !recoveringConnection)) {
      return null;
    }
    final opening = _opening = _RemoteOpening(
      presentation.beginStart(),
      recoveringConnection,
    );
    final attempt = opening.ticket;
    bool accepts() => isCurrent && presentation.acceptsStart(attempt);
    var submittedAppStart = false;
    try {
      await releaseInputs();
      if (!accepts() || !canProceed()) return null;
      presentation.replaceBinding();
      var retained = recoveringConnection || presentation.appLaunchClosed
          ? null
          : existing;
      if (retained != null &&
          (retained.deviceId != deviceId ||
              retained.session.packageName != packageName)) {
        throw const RequestFailure('stale_session', '现有会话不属于当前控制窗口。');
      }
      if (retained == null) {
        final listed = await videos.readVideoSessions(deviceId: deviceId);
        if (!accepts() || !canProceed()) return null;
        retained = listed.where((view) {
          final session = view.session;
          return session.deviceId == deviceId &&
              session.packageName == packageName &&
              !session.recordOnly &&
              (session.launchOutcome == .unknown || session.live);
        }).firstOrNull;
      }
      if (retained?.session.launchOutcome == .unknown) {
        presentation.showUnknownAppLaunch(retained);
        return null;
      }
      VideoSessionView result;
      if (retained != null) {
        result = retained;
      } else {
        final plan = await prepare(() => accepts() && canProceed());
        if (plan == null || !accepts() || !canProceed()) return null;
        if (plan.deviceId != deviceId || plan.packageName != packageName) {
          throw const RequestFailure('invalid_argument', '打开意图不属于当前控制窗口。');
        }
        submittedAppStart = packageName != null;
        result = await videos.startVideo(plan);
      }
      if (result.deviceId != deviceId ||
          result.session.packageName != packageName) {
        throw const RequestFailure('stale_session', '会话回执不属于当前控制窗口。');
      }
      if (!accepts()) {
        if (isCurrent && presentation.requiresVerification(attempt)) {
          // 状态中断后只保留已提交身份，不能重开或停止可能仍存活的真实任务。
          presentation.retainUnverifiedStart(result);
        } else if (retained == null &&
            result.sessionId.isNotEmpty &&
            result.sessionId != presentation.sessionId) {
          try {
            await videos.stopVideo(
              ControlTarget(sessionId: result.sessionId),
              keepLaunchRecord: packageName != null,
            );
          } catch (_) {
            // 精确捕获的释放失败仍由执行所有者保留，不能复活原窗口。
          }
        }
        return null;
      }
      final submitted = submittedAppStart;
      submittedAppStart = false;
      presentation.bindStart(
        result,
        retained: retained != null,
        recoveringConnection: recoveringConnection,
        submittedAppStart: submitted,
      );
      if (result.sessionId.isNotEmpty && result.textureId != null) {
        bind(visible: result.session.status != .paused);
      }
      return RemoteWindowOpened(result, retained != null, attempt);
    } catch (failure) {
      if (accepts()) {
        presentation.failStart(
          remoteFailure(failure),
          remoteFailureCode(failure),
          submittedAppStart: submittedAppStart,
          uncertainSession: switch (failure) {
            VideoStartUncertain(:final session) => _unverifiedView(session),
            AppLaunchUncertain(:final record) => _unverifiedView(
              record.snapshot,
            ),
            _ => null,
          },
        );
      }
      return null;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  VideoSessionView _unverifiedView(VideoSessionSnapshot session) =>
      VideoSessionView(
        session: session,
        wake:
            presentation.session?.wake ??
            KeepAwakeSnapshot.withoutLease(
              deviceId: deviceId,
              enabled: false,
              hasWindowOwner: false,
            ),
      );

  void cancelRecovery() {
    if (!recoveringConnection) return;
    presentation.invalidateStart();
    _opening = null;
    presentation.deferStart();
  }

  Future<void> checkAppLaunch(String? packageName) async {
    if (!isCurrent || presentation.exiting) return;
    final attempt = presentation.beginStart();
    try {
      final listed = await videos.readVideoSessions(deviceId: deviceId);
      if (!isCurrent || !presentation.acceptsStart(attempt)) return;
      final record = listed.where((view) {
        final session = view.session;
        return session.deviceId == deviceId &&
            (presentation.sessionId.isNotEmpty
                ? session.sessionId == presentation.sessionId
                : session.packageName == packageName);
      }).firstOrNull;
      presentation.showUnknownAppLaunch(record ?? presentation.session);
    } catch (failure) {
      if (isCurrent && presentation.acceptsStart(attempt)) {
        presentation.failOperation(remoteFailure(failure));
      }
    }
  }

  Future<bool> closeAppLaunchRecord({required bool resetInitialAction}) async {
    if (!isCurrent || presentation.exiting) return false;
    final attempt = presentation.beginStart();
    final id = presentation.sessionId;
    try {
      if (id.isNotEmpty) await videos.stopVideo(ControlTarget(sessionId: id));
      if (!isCurrent || !presentation.acceptsStart(attempt)) return false;
      presentation.closeUnknownAppLaunch(
        resetInitialAction: resetInitialAction,
      );
      return true;
    } catch (failure) {
      if (isCurrent && presentation.acceptsStart(attempt)) {
        presentation.failOperation(remoteFailure(failure));
      }
      return false;
    }
  }

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

  void detachUnknownLaunch(
    AppLaunchRecord record,
    Future<void> Function() releaseInputs,
  ) {
    final outgoing = presentation.permitDetachedCleanup();
    final releases = releaseInputs().whenComplete(() {
      presentation.finishDetachedCleanup(outgoing);
    });
    final owned = _view;
    _view = null;
    presentation.detachBinding();
    if (owned != null) {
      unawaited(owned.release(afterInput: releases));
    }
    // 操作记录的检查不依赖旧输入或捕获暂停的回执。
    presentation.showUnknownAppLaunch(_unverifiedView(record.snapshot));
  }

  Future<String?> verifiedForegroundApp({
    required bool Function() canSendInput,
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
    final captureGeneration = presentation.session?.session.captureGeneration;
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
                  captureGeneration: captureGeneration,
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
      await owned.close(afterInput: release);
    }
    await release;
  }
}

/// 同次启动的回执与呈现许可；页面只可在该许可仍有效时继续附着视图。
final class RemoteWindowOpened {
  const RemoteWindowOpened(this.view, this.retained, this.ticket);
  final VideoSessionView view;
  final bool retained;
  final RemoteStartTicket ticket;
}

final class _RemoteOpening {
  const _RemoteOpening(this.ticket, this.recoveringConnection);
  final RemoteStartTicket ticket;
  final bool recoveringConnection;
}
