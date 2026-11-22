import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/settings/metadata_management.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';

import 'models/metadata_operation_state.dart';

part 'metadata_operation_notifier.g.dart';

/// 同页串行迁移记录；选择器和预览由页面呈现，离页不撤销已提交的导入。
@riverpod
class MetadataOperationNotifier extends _$MetadataOperationNotifier {
  late _MetadataOwner _owner;

  @override
  MetadataOperationState build({required Object scope}) {
    final owner = _owner = _MetadataOwner(
      ref.watch(metadataManagementProvider),
      ref.watch(settingsManagementProvider),
      ref.watch(deviceReaderProvider),
      ref.watch(stateSubscriptionProvider),
    );
    ref.onDispose(() => owner.disposed = true);
    return const MetadataOperationState();
  }

  bool _current(_MetadataOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      !owner.subscription.disposed &&
      identical(_owner, owner) &&
      identical(ref.read(metadataManagementProvider), owner.metadata) &&
      identical(ref.read(settingsManagementProvider), owner.settings) &&
      identical(ref.read(deviceReaderProvider), owner.devices) &&
      identical(ref.read(stateSubscriptionProvider), owner.subscription);

  Future<void> importRecords({
    required Future<String?> Function() pickFile,
    required Future<bool?> Function(SettingsImportPreview) confirm,
  }) => _run('导入记录未完成', (owner) async {
    final path = await pickFile();
    if (!_current(owner) || path == null) return;
    // 限量读取，选择器返回路径后文件也可能变化，不能只依赖 length 检查。
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead()) {
      if (!_current(owner)) return;
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const RequestFailure(
          'metadata_file_too_large',
          '设备记录文件须小于 1 MB。',
        );
      }
      bytes.add(chunk);
    }
    if (!_current(owner)) return;
    final metadata = DeviceMetadata.parse(
      jsonDecode(utf8.decode(bytes.takeBytes())),
    );
    final preview = await owner.metadata.previewImport(metadata);
    if (!_current(owner)) return;
    final importGlobal = await confirm(preview);
    if (!_current(owner) || importGlobal == null) return;
    final result = await owner.metadata.importMetadata(
      preview,
      importGlobalPreferences: importGlobal,
    );
    if (!_current(owner)) return;
    state = const MetadataOperationState(busy: true, refreshPending: true);
    await _refresh(owner);
    if (!_current(owner)) return;
    if (!state.refreshPending) {
      state = MetadataOperationState(
        busy: true,
        message: result.records.alreadyImported
            ? '此文件已导入，已核对本机记录。'
            : '设备记录已导入。请在手机上重新允许调试。',
      );
    }
  });

  Future<void> exportRecords({
    required Future<Uri?> Function(Uint8List bytes) saveFile,
  }) => _run('保存记录未完成', (owner) async {
    final metadata = await owner.metadata.exportMetadata();
    if (!_current(owner)) return;
    final saved = await saveFile(
      Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent('  ').convert(metadata.document),
        ),
      ),
    );
    if (!_current(owner) || saved == null) return;
    state = MetadataOperationState(
      busy: true,
      refreshPending: state.refreshPending,
      message: '设备记录已保存至 $saved',
    );
  });

  /// 只重新读取本机状态，不重放已经提交的导入。
  Future<void> refreshRecords() => _run('重新加载记录未完成', (owner) async {
    if (!state.refreshPending) return;
    await _refresh(owner);
    if (_current(owner) && !state.refreshPending) {
      state = const MetadataOperationState(
        busy: true,
        message: '设备记录已导入，界面已重新加载。',
      );
    }
  });

  Future<void> _refresh(_MetadataOwner owner) async {
    try {
      await ref.read(preferencesProvider.notifier).load();
      if (!_current(owner)) return;
      await ref.read(deviceListProvider.notifier).refresh();
      if (!_current(owner)) return;
      if (ref.read(preferencesProvider).error != null ||
          ref.read(deviceListProvider).error != null) {
        throw const FormatException('本机状态尚未读取完成。');
      }
      state = const MetadataOperationState(busy: true);
    } catch (_) {
      if (_current(owner)) {
        state = const MetadataOperationState(
          busy: true,
          refreshPending: true,
          message: '设备记录已导入。请点「重新加载记录」，无需再次导入。',
        );
      }
    }
  }

  Future<void> _run(
    String failure,
    Future<void> Function(_MetadataOwner) action,
  ) async {
    if (!ref.mounted || state.busy) return;
    final owner = _owner;
    if (!_current(owner)) return;
    state = MetadataOperationState(
      busy: true,
      refreshPending: state.refreshPending,
    );
    try {
      await action(owner);
    } catch (error) {
      if (_current(owner)) {
        state = MetadataOperationState(
          busy: true,
          refreshPending: state.refreshPending,
          message: failureMessage(error, fallback: '$failure。请检查所选文件或位置后重试。'),
        );
      }
    } finally {
      if (_current(owner)) {
        state = MetadataOperationState(
          refreshPending: state.refreshPending,
          message: state.message,
        );
      }
    }
  }
}

final class _MetadataOwner {
  _MetadataOwner(this.metadata, this.settings, this.devices, this.subscription);
  final MetadataManagement metadata;
  final SettingsManagement settings;
  final DeviceReader devices;
  final StateSubscription subscription;
  bool disposed = false;
}
