import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart' show LocalFiles;
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_desktop_delivery.dart';
import 'package:scrcpy_connect/core/files/file_document_cache.dart';
import 'package:scrcpy_connect/core/files/file_document_recovery.dart';
import 'package:scrcpy_connect/core/files/file_document_scope.dart';
import 'package:scrcpy_connect/core/files/file_document_service.dart';
import 'package:scrcpy_connect/core/files/file_selection_requests.dart';
import 'package:scrcpy_connect/core/files/system_document_backend.dart';

/// 文档宿主协议、执行端选择与跨 isolate 接管；不承担应用级平台职责。
final class FileDocumentPlatform {
  FileDocumentPlatform({
    required this.files,
    required this._request,
    required this.isDisposed,
  });
  final Future<LocalFiles> Function() files;
  final Future<Json> Function(String, Json) _request;
  final bool Function() isDisposed;
  static FileDocumentRecovery? _recovery;
  Future<void>? _recovering;

  bool get available => Platform.isAndroid || Platform.isLinux;
  bool get allowImport => Platform.isAndroid;

  Future<void> recover() async {
    if (Platform.isLinux) {
      await FileDesktopDelivery.recover(
        files,
        await Directory.systemTemp.resolveSymbolicLinks(),
      );
    } else if (Platform.isAndroid) {
      await _confirmRecovery();
    }
  }

  Future<void> _confirmRecovery() => _recovering ??= () async {
    final recovery = _recovery ??= FileDocumentRecovery(
      files: files,
      platform: _request,
    );
    await recovery.recover();
    // 失败仍保留精确候选，下一次恢复不能按 ready 跳过未完成接管。
    if (identical(_recovery, recovery)) _recovery = null;
  }().whenComplete(() => _recovering = null);

  Future<Json> request(String command, Json params) async {
    var result = await _request(command, params);
    if (command != 'documents.platform.environment') return result;
    void check() {
      if (isDisposed()) throw const RequestFailure('cancelled', '文档服务正在关闭。');
    }

    check();
    if (result['ownerReady'] == false || _recovery != null) {
      await _confirmRecovery();
      check();
      result = await _request(command, params);
      if (result['ownerReady'] != true) {
        throw const RequestFailure(
          'document_cleanup_unconfirmed',
          '平台文档资源尚未完成接管。',
        );
      }
    }
    return (await FileDocumentScope.fromEnvironment(result)).environment;
  }

  SystemDocumentBackend createBackend({
    required FileSelectionRequests selections,
    required FileDocumentCache? sources,
    required void Function(Json) conflictChanged,
  }) {
    if (Platform.isAndroid) {
      return FileDocumentService(
        selections: selections,
        files: files,
        platform: request,
        isDisposed: isDisposed,
        sources: sources,
        onConflictChanged: conflictChanged,
      );
    }
    if (Platform.isLinux) {
      return FileDesktopDelivery(
        selections: selections,
        files: files,
        emit: conflictChanged,
      );
    }
    throw const RequestFailure('platform_unavailable', '此平台尚不支持系统位置保存。');
  }

  Future<void> close() async {
    if (_recovery != null) await _confirmRecovery();
  }
}
