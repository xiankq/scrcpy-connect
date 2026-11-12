import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_capabilities_provider.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';

import 'models/share_submission_state.dart';

part 'share_submission_notifier.g.dart';

/// 一次页面确认的执行所有者；离页只撤销后续步骤，不停止已经登记的传输。
@riverpod
class ShareSubmissionNotifier extends _$ShareSubmissionNotifier {
  late _ShareSubmissionOwner _owner;

  @override
  ShareSubmissionState build(String shareId, {required Object scope}) {
    final owner = _owner = _ShareSubmissionOwner(
      incoming: ref.watch(incomingSharesProvider),
      directories: ref.watch(fileDirectoriesProvider),
      transfers: ref.watch(fileTransfersProvider),
      clipboard: ref.watch(remoteClipboardProvider),
      events: ref.watch(runtimeEventsProvider),
    );
    ref.onDispose(owner.dispose);
    return const ShareSubmissionState();
  }

  bool _current(_ShareSubmissionOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      identical(ref.read(incomingSharesProvider), owner.incoming) &&
      identical(ref.read(fileDirectoriesProvider), owner.directories) &&
      identical(ref.read(fileTransfersProvider), owner.transfers) &&
      identical(ref.read(remoteClipboardProvider), owner.clipboard) &&
      identical(ref.read(runtimeEventsProvider), owner.events) &&
      identical(_owner, owner);

  IncomingShare? _pending() => ref
      .read(shareInboxProvider)
      .shares
      .where((share) => share.shareId == shareId)
      .firstOrNull;

  Future<void> _finish(
    _ShareSubmissionOwner owner, {
    bool showTransfers = false,
  }) async {
    if (!_current(owner)) return;
    if (_pending() != null) {
      await ref.read(shareInboxProvider.notifier).consume(shareId);
    }
    if (!_current(owner)) return;
    state = state.copyWith(
      completed: true,
      showTransfers: showTransfers && state.pushed,
    );
  }

  Future<void> cancel() async {
    if (state.busy || state.completed) return;
    final owner = _owner;
    state = state.copyWith(busy: true, error: null);
    try {
      await _finish(owner);
    } catch (error) {
      if (_current(owner)) {
        state = state.copyWith(error: '暂时无法关闭本次分享：$error');
      }
    } finally {
      if (_current(owner)) state = state.copyWith(busy: false);
    }
  }

  Future<void> submit({
    required String? deviceId,
    required String directory,
    required bool includeFiles,
    required bool includeText,
  }) async {
    if (state.busy || state.completed) return;
    final owner = _owner;
    state = state.copyWith(busy: true, error: null);
    try {
      final share = _pending();
      if (share == null) {
        throw const RequestFailure('missing_share', '这次分享已处理，请重新从系统分享。');
      }
      if ({
        IncomingShareStatus.starting,
        IncomingShareStatus.importing,
      }.contains(share.status)) {
        throw const RequestFailure('share_importing', '分享内容还未准备完成。');
      }
      final push = includeFiles && share.files.isNotEmpty && !state.pushed;
      final copy = includeText && share.text.isNotEmpty && !state.copied;
      if (!push && !copy && !state.pushed && !state.copied) {
        throw const RequestFailure('share_empty_selection', '请选择要发送的内容。');
      }
      final readiness = deviceId == null
          ? null
          : ref.read(deviceReadinessProvider(deviceId));
      bool admitted() {
        if (!_current(owner)) return false;
        if (_pending() == null) {
          throw const RequestFailure('missing_share', '这次分享已处理，请重新从系统分享。');
        }
        if (deviceId == null ||
            readiness?.ready != true ||
            ref.read(deviceReadinessProvider(deviceId)) != readiness) {
          throw const RequestFailure('device_unavailable', '设备连接已变化，请重新核对目标。');
        }
        return true;
      }

      if (push) {
        if (!admitted()) return;
        final path = FilePaths.remote(directory.trim());
        final cancellation = owner.directoryRead = FileCancellation();
        final result = await owner.directories.readDirectory((
          deviceId: deviceId!,
          path: path,
        ), cancellation: cancellation);
        owner.directoryRead = null;
        if (!admitted()) return;
        if (result.deviceId != deviceId || result.path != path) {
          throw const RequestFailure('missing_directory', '目标设备或目录无法核验，请重新选择。');
        }
        await owner.transfers.startTransfer(
          FileTransferPlan(
            deviceId: deviceId,
            direction: .push,
            items: [
              for (final file in share.files)
                FileTransferSelection(
                  source: file.localPath,
                  destination:
                      '${path == '/' ? '' : path}/${FilePaths.name(file.name)}',
                ),
            ],
          ),
          shareId: shareId,
        );
        if (!_current(owner)) return;
        state = state.copyWith(pushed: true);
      }
      if (copy) {
        if (!admitted()) return;
        await owner.clipboard.writeClipboard(
          ClipboardTarget.device(deviceId: deviceId!),
          share.text,
        );
        if (!_current(owner)) return;
        state = state.copyWith(copied: true);
      }
      await _finish(owner, showTransfers: true);
    } catch (error) {
      if (_current(owner)) state = state.copyWith(error: '$error');
    } finally {
      owner.directoryRead = null;
      if (_current(owner)) state = state.copyWith(busy: false);
    }
  }
}

final class _ShareSubmissionOwner {
  _ShareSubmissionOwner({
    required this.incoming,
    required this.directories,
    required this.transfers,
    required this.clipboard,
    required this.events,
  });
  final IncomingShares incoming;
  final FileDirectories directories;
  final FileTransfers transfers;
  final RemoteClipboard clipboard;
  final Stream<RuntimeEvent> events;
  FileCancellation? directoryRead;
  bool disposed = false;

  void dispose() {
    disposed = true;
    directoryRead?.cancel();
  }
}
