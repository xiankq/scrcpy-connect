import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:json_annotation/json_annotation.dart'
    show CheckedFromJsonException;
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/files/file_delivery.dart';
import 'package:scrcpy_connect/core/files/file_selection_requests.dart';

import 'package:scrcpy_connect/core/files/file_document_scope.dart';

import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart' show LocalFiles;
import 'package:scrcpy_connect/core/files/file_desktop_delivery.dart';

import 'package:scrcpy_connect/core/files/file_document_service.dart';
import 'package:scrcpy_connect/core/files/file_document_cache.dart';
import 'package:scrcpy_connect/core/files/file_document_recovery.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/files/file_export_service.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:flutter/services.dart';
import 'package:scrcpy_connect/core/media/audio_focus_service.dart';

import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 拥有宿主授权、系统文档交付及平台事件适配。
final class ApplicationPlatform implements BackgroundControl, SystemDocuments {
  ApplicationPlatform({
    required this.deliveries,
    required this.localFiles,
    this.sharing,
    this.documentSources,
    required this.emit,
    required this.isDisposed,
    this.usbOwnerLeaseId,
  });
  final FileDeliveryRecords deliveries;
  final Future<LocalFiles> Function() localFiles;
  final FileShareService? sharing;
  final FileDocumentCache? documentSources;
  final void Function(Map<String, dynamic>) emit;
  final bool Function() isDisposed;

  /// 初始化恢复确认后取得的本代权限；旧实例永不读取或借用后继权限。
  final String? usbOwnerLeaseId;
  bool _closing = false;
  bool get _disposed => _closing || isDisposed();
  static const _channel = MethodChannel('dev.scrcpyconnect/platform');
  static const _events = EventChannel('dev.scrcpyconnect/media_events');

  static FileDocumentRecovery? _documentRecovery;

  /// 缓存恢复必须等待此栅栏；非 Android 宿主没有平台文档 worker。
  static Future<void> recoverDocuments({
    required Future<LocalFiles> Function() localFiles,
  }) async {
    if (Platform.isLinux) {
      await FileDesktopDelivery.recover(
        localFiles,
        await Directory.systemTemp.resolveSymbolicLinks(),
      );
      return;
    }
    if (!Platform.isAndroid) return;
    await _confirmDocumentRecovery(localFiles);
  }

  static FileDocumentRecovery _recovery(Future<LocalFiles> Function() files) =>
      _documentRecovery ??= FileDocumentRecovery(
        files: files,
        platform: requestPlatform,
      );

  static Future<void> _confirmDocumentRecovery(
    Future<LocalFiles> Function() files,
  ) async {
    final recovery = _recovery(files);
    await recovery.recover();
    // 成功确认后结束此恢复所有权；失败继续保留原候选及尚未关闭的资源。
    if (identical(_documentRecovery, recovery)) _documentRecovery = null;
  }

  static Future<Map<String, dynamic>> requestPlatform(
    String command,
    Map<String, dynamic> params,
  ) async {
    final result = await _channel.invokeMethod<Object?>(command, params);
    return result is Map<Object?, Object?>
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void>? _recoveringDocuments;

  Future<void> _recoverDocumentOwner() {
    final running = _recoveringDocuments;
    if (running != null) return running;
    final recovery = _confirmDocumentRecovery(localFiles);
    _recoveringDocuments = recovery;
    return recovery.whenComplete(() => _recoveringDocuments = null);
  }

  Stream<dynamic> get events => _events.receiveBroadcastStream();
  late final documentSelections = FileSelectionRequests((selection) {
    emit({'type': 'documents.selection.requested', 'data': selection});
  });
  late final _documents = FileDocumentService(
    selections: documentSelections,
    files: localFiles,
    platform: request,
    isDisposed: () => _disposed,
    sources: documentSources,
    onConflictChanged: (data) {
      if (!_disposed) {
        emit({'type': 'documents.conflict.changed', 'data': data});
      }
    },
  );
  late final _systemDelivery = FileExportService(
    deliveries: deliveries,
    write: (params) => Platform.isAndroid
        ? _documents.exportDocument(params)
        : _desktopDocuments.write(params),
    cancelWrite: (id) => Platform.isAndroid
        ? _documents.cancel(id)
        : _desktopDocuments.cancel(id),
    onChanged: (source) {
      if (!_disposed) {
        emit({'type': 'delivery.changed', 'data': source.toJson()});
      }
    },
  );
  late final _desktopDocuments = FileDesktopDelivery(
    selections: documentSelections,
    files: localFiles,
    emit: (data) {
      if (!_disposed) {
        emit({'type': 'documents.conflict.changed', 'data': data});
      }
    },
  );
  Future<Map<String, dynamic>> audioRequest(
    String command,
    Map<String, dynamic> params,
  ) async {
    try {
      return await request(command, params);
    } on PlatformException catch (error) {
      throw RequestFailure(error.code, error.message ?? '系统声音操作未完成。');
    }
  }

  late final _mixerAudio = AudioFocusService(
    backgroundPlaybackSupported: !Platform.isIOS,
  );

  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> params,
  ) async {
    if (!Platform.isAndroid && command.startsWith('audio.platform.')) {
      return _mixerAudio.request(command, params);
    }
    var response = await requestPlatform(command, params);
    if (command == 'documents.platform.environment') {
      if (_disposed) {
        throw const RequestFailure('cancelled', '文档服务正在关闭。');
      }
      if (response['ownerReady'] == false || _documentRecovery != null) {
        // 丢失接管回执时仍须确认原候选；不能因平台已 ready 而跳过未完成恢复。
        await _recoverDocumentOwner();
        if (_disposed) {
          throw const RequestFailure('cancelled', '文档服务正在关闭。');
        }
        response = await requestPlatform(command, params);
        if (response['ownerReady'] != true) {
          throw const RequestFailure(
            'document_cleanup_unconfirmed',
            '平台文档资源尚未完成接管。',
          );
        }
      }
      return (await FileDocumentScope.fromEnvironment(response)).environment;
    }
    return response;
  }

  void _requireDocuments() {
    if (_disposed) throw const RequestFailure('cancelled', '文档服务正在关闭。');
    if (!Platform.isAndroid && !Platform.isLinux) {
      throw const RequestFailure(
        'platform_unavailable',
        '此平台尚不支持可核验的系统位置保存，请使用系统文件分享并在接收应用核对。',
      );
    }
  }

  @override
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  ) {
    _requireDocuments();
    if (!Platform.isAndroid) {
      throw const RequestFailure('platform_unavailable', '此桌面入口仅支持保存本机原件。');
    }
    return _documents.importDocuments(operationId, kind);
  }

  @override
  Future<DocumentOutcome> exportDocument(DocumentExportPlan plan) {
    _requireDocuments();
    return _systemDelivery.save(plan);
  }

  @override
  Future<void> cancelDocument(String operationId) async {
    _requireDocuments();
    if (await _systemDelivery.cancel(operationId)) return;
    if (Platform.isAndroid) {
      await _documents.cancel(operationId);
    } else {
      await _desktopDocuments.cancel(operationId);
    }
  }

  @override
  Future<void> releaseDocumentSource(String managedSourceId) async {
    _requireDocuments();
    await _documents.releaseSource(managedSourceId);
  }

  @override
  Future<DocumentConflict?> readDocumentConflict(String operationId) {
    _requireDocuments();
    return Platform.isAndroid
        ? _documents.readConflict(operationId)
        : _desktopDocuments.readConflict(operationId);
  }

  @override
  Future<bool> resolveDocumentConflict(
    String operationId,
    String conflictId,
    DocumentConflictDecision decision, {
    bool applyToRemaining = false,
  }) {
    _requireDocuments();
    return Platform.isAndroid
        ? _documents.resolveConflict(
            operationId,
            conflictId,
            decision,
            applyToRemaining: applyToRemaining,
          )
        : _desktopDocuments.resolveConflict(
            operationId,
            conflictId,
            decision,
            applyToRemaining: applyToRemaining,
          );
  }

  @override
  Future<FileDeliveryRecord?> readDelivery(DocumentSource source) {
    if (_disposed) throw const RequestFailure('cancelled', '文档服务正在关闭。');
    return deliveries.read(source);
  }

  @override
  Future<BackgroundStatus> readBackgroundStatus() =>
      _readBackground('background.status', const {});

  @override
  Future<BackgroundStatus> requestBackground({
    required bool enabled,
    bool automatic = false,
    bool askNotificationPermission = false,
  }) => _readBackground('background.request', {
    'enabled': enabled,
    'automatic': automatic,
    'askNotificationPermission': askNotificationPermission,
  });

  Future<BackgroundStatus> _readBackground(
    String method,
    Map<String, Object?> params,
  ) async {
    void check() {
      if (_disposed) throw const RequestFailure('disposed', '应用平台已关闭。');
    }

    check();
    if (!Platform.isAndroid) {
      return BackgroundStatus(
        platform: Platform.operatingSystem,
        title: Platform.isIOS
            ? 'iOS 后台限制'
            : Platform.isMacOS || Platform.isWindows || Platform.isLinux
            ? '桌面进程中的活动'
            : '后台能力尚未确认',
        reason: Platform.isIOS
            ? 'iOS 当前不支持通用持续后台保持。离开 App 后，连接、传输及提醒可能暂停；请返回前台后核对活动。'
            : Platform.isMacOS || Platform.isWindows || Platform.isLinux
            ? '连接与传输依赖应用进程继续运行。系统休眠、退出或结束进程后不保证活动继续；再次打开会核对实际状态。'
            : '当前平台未确认持续后台能力。请保持 App 在前台，并核对活动的实际状态。',
      );
    }
    try {
      final result = await requestPlatform(method, params);
      check();
      return BackgroundStatus.fromJson(result);
    } on CheckedFromJsonException catch (_, stack) {
      Error.throwWithStackTrace(
        const RequestFailure('background_status_invalid', '未能核验系统后台状态，请重新检查。'),
        stack,
      );
    } on PlatformException catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message ?? '系统后台操作未完成。'),
        stack,
      );
    }
  }

  Future<Map<String, dynamic>> authorizeUsb(Map<String, dynamic> params) async {
    if (_disposed) {
      throw const RequestFailure('cancelled', 'USB 授权已停止。');
    }
    final owned = _usbParams(params);
    try {
      final permission = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'usb.authorize',
        owned,
      );
      if (permission == null) {
        throw const RequestFailure('cancelled', '尚未允许 USB 访问。');
      }
      if (permission['ownerLeaseId'] != usbOwnerLeaseId) {
        throw const RequestFailure('usb_owner_mismatch', 'USB 授权回执不属于本次平台权限。');
      }
      // 成功回执可能晚于取消或 dispose；仍交回精确 lease，由 setup 排空后释放。
      return Map<String, dynamic>.from(permission);
    } on PlatformException catch (error) {
      throw RequestFailure(
        error.code,
        error.message ?? 'USB 访问未完成，请重新检查。',
        error.details,
      );
    }
  }

  Map<String, dynamic> _usbParams(Map<String, dynamic> params) {
    final owner = usbOwnerLeaseId;
    if (owner == null ||
        owner.length > 256 ||
        owner.trim().isEmpty ||
        owner.runes.any((code) => code < 32 || code >= 127 && code <= 159)) {
      throw const RequestFailure('usb_owner_unavailable', '尚未完成本机 USB 资源恢复。');
    }
    return {...params, 'ownerLeaseId': owner};
  }

  /// 精确清理不受页面或应用 dispose 阻断，失败保留调用方原 lease 的重试权。
  Future<void> cancelUsb(Map<String, dynamic> params) async =>
      _cleanupUsb('usb.cancel', 'cancelled', params);
  Future<void> releaseUsb(Map<String, dynamic> params) async =>
      _cleanupUsb('usb.release', 'released', params);

  Future<void> _cleanupUsb(
    String command,
    String confirmation,
    Map<String, dynamic> params,
  ) async {
    final owned = _usbParams(params);
    final response = await _channel.invokeMethod<Object?>(command, owned);
    if (response is! Map<Object?, Object?> ||
        response[confirmation] != true ||
        response['ownerLeaseId'] != usbOwnerLeaseId) {
      throw const RequestFailure(
        'usb_cleanup_unconfirmed',
        'USB 平台尚未确认原资源已回收，请保留原权限与标识重试。',
      );
    }
  }

  Future<void> attachShare() async {
    await sharing?.configure();
    unawaited(
      (sharing?.attach() ?? Future<void>.value()).catchError((Object error) {
        if (!_disposed) {
          emit({
            'type': 'sharing.failed',
            'data': {'reason': '$error'},
          });
        }
      }),
    );
  }

  Future<void> handleShare(Map<String, dynamic> data) async {
    try {
      await sharing?.receive(data);
    } catch (error) {
      if (!_disposed) {
        emit({
          'type': 'sharing.failed',
          'data': {'reason': '$error'},
        });
      }
    }
  }

  OrderedDisposal? _disposal;
  Future<void> dispose() {
    _closing = true;
    _systemDelivery.close();
    _disposal ??= OrderedDisposal([
      _documents.dispose,
      _desktopDocuments.dispose,
      () async {
        if (_documentRecovery != null) await _recoverDocumentOwner();
      },
    ]);
    return _disposal!.run();
  }
}
