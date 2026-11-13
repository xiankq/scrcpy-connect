import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_import_receipt.dart';
import 'package:scrcpy_connect/core/devices/models/device_metadata.dart';
import 'package:scrcpy_connect/core/devices/models/device_records_import.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/settings/metadata_management.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/pages/settings/data_preferences/metadata_operation_notifier.dart';

void main() {
  late Directory directory;
  late File input;
  late _Metadata metadata;
  late _Settings settings;
  late _Devices devices;
  late ProviderContainer container;
  late MetadataOperationNotifier actions;
  late void Function() leave;
  final scope = Object();
  final provider = metadataOperationProvider(scope: scope);
  final source = Provider((ref) => metadata);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('metadata-operation-');
    input = await File('${directory.path}/records.json')
        .writeAsString(jsonEncode(_document));
    metadata = _Metadata();
    settings = _Settings();
    devices = _Devices();
    container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(AppSession(initialize: false)),
        metadataManagementProvider.overrideWith((ref) => ref.watch(source)),
        settingsManagementProvider.overrideWithValue(settings),
        deviceReaderProvider.overrideWithValue(devices),
      ],
    );
    leave = container.listen(provider, (_, _) {}).close;
    actions = container.read(provider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  test('从选择器到导入刷新共用忙碌门禁，冻结预览内容且不重复提交', () async {
    final picked = Completer<String?>();
    final pending = actions.importRecords(
      pickFile: () => picked.future,
      confirm: (preview) async {
        await input.writeAsString('changed after preview');
        expect(preview.metadata.document['devices'], isEmpty);
        return false;
      },
    );
    expect(container.read(provider).busy, isTrue);
    await actions.importRecords(
      pickFile: () => throw StateError('duplicate'),
      confirm: (_) async => true,
    );
    await actions.exportRecords(
      saveFile: (_) => throw StateError('duplicate export'),
    );
    picked.complete(input.path);
    await pending;
    expect(metadata.imports, 1);
    expect(metadata.importGlobal, isFalse);
    expect(settings.reads, 1);
    expect(devices.reads, 1);
    expect(container.read(provider).busy, isFalse);
    expect(container.read(provider).refreshPending, isFalse);
    expect(container.read(provider).message, contains('设备记录已导入'));
  });

  test('刷新读取失败保留导入结果，重新加载不再预览或提交导入', () async {
    settings.failure = true;
    await actions.importRecords(
      pickFile: () async => input.path,
      confirm: (_) async => true,
    );
    expect(container.read(provider).refreshPending, isTrue);
    expect(container.read(provider).message, contains('无需再次导入'));
    expect(metadata.imports, 1);
    settings.failure = false;
    devices.failure = true;
    await actions.refreshRecords();
    expect(container.read(provider).refreshPending, isTrue);
    devices.failure = false;
    await actions.refreshRecords();
    expect(container.read(provider).refreshPending, isFalse);
    expect(container.read(provider).message, contains('界面已重新加载'));
    expect(metadata.imports, 1);
    expect(metadata.previews, 1);
  });

  test('取消选择或预览、无效及超限文件都不提交并解除忙碌', () async {
    await actions.importRecords(
      pickFile: () async => null,
      confirm: (_) => throw StateError('no preview'),
    );
    await actions.importRecords(
      pickFile: () async => input.path,
      confirm: (_) async => null,
    );
    expect(metadata.imports, 0);
    expect(container.read(provider).message, isNull);
    await input.writeAsString('invalid');
    await actions.importRecords(
      pickFile: () async => input.path,
      confirm: (_) => throw StateError('invalid preview'),
    );
    expect(container.read(provider).message, contains('导入记录未完成'));
    await input.writeAsBytes(List.filled(1024 * 1024 + 1, 32));
    await actions.importRecords(
      pickFile: () async => input.path,
      confirm: (_) => throw StateError('oversize preview'),
    );
    expect(container.read(provider).message, contains('1 MB'));
    expect(container.read(provider).busy, isFalse);
    expect(metadata.previews, 1);
    expect(metadata.imports, 0);
  });

  test('预览期间能力换源，旧确认不能提交或覆盖新操作', () async {
    final confirming = Completer<void>();
    final decision = Completer<bool?>();
    final original = metadata;
    final old = actions.importRecords(
      pickFile: () async => input.path,
      confirm: (_) {
        confirming.complete();
        return decision.future;
      },
    );
    await confirming.future;
    metadata = _Metadata();
    container.invalidate(source);
    final saving = Completer<Uri?>();
    final next = container
        .read(provider.notifier)
        .exportRecords(saveFile: (_) => saving.future);
    decision.complete(true);
    await old;
    expect(original.imports, 0);
    expect(container.read(provider).busy, isTrue);
    saving.complete(null);
    await next;
    expect(container.read(provider).message, isNull);
  });

  test('离页后不展示迟到预览，已提交导入结算不刷新或重放', () async {
    final picked = Completer<String?>();
    final selecting = actions.importRecords(
      pickFile: () => picked.future,
      confirm: (_) => throw StateError('retired preview'),
    );
    leave();
    await container.pump();
    picked.complete(input.path);
    await selecting;
    expect(metadata.previews, 0);
    leave = container.listen(provider, (_, _) {}).close;
    actions = container.read(provider.notifier);
    final submitted = Completer<void>();
    metadata.pending = Completer<SettingsImportResult>();
    metadata.onImport = submitted.complete;
    final importing = actions.importRecords(
      pickFile: () async => input.path,
      confirm: (_) async => true,
    );
    await submitted.future;
    leave();
    await container.pump();
    metadata.pending!.complete(_result());
    await importing;
    expect(metadata.imports, 1);
    expect(settings.reads, 0);
    expect(devices.reads, 0);
  });

  test('导出使用序列化字节，取消不报成功，离页后不打开保存器', () async {
    await actions.exportRecords(
      saveFile: (bytes) async {
        expect(
          DeviceMetadata.parse(jsonDecode(utf8.decode(bytes))).fingerprint,
          DeviceMetadata.parse(_document).fingerprint,
        );
        return null;
      },
    );
    expect(container.read(provider).message, isNull);
    final pending = Completer<DeviceMetadata>();
    metadata.exporting = pending.future;
    final exporting = actions.exportRecords(
      saveFile: (_) => throw StateError('retired save'),
    );
    leave();
    await container.pump();
    pending.complete(DeviceMetadata.parse(_document));
    await exporting;
  });
}

const _document = {
  'format': 'scrcpy-connect-metadata',
  'version': 1,
  'devices': <Object?>[],
};
SettingsImportResult _result() => SettingsImportResult(
  records: DeviceRecordsImport(
    'fingerprint',
    DeviceImportReceipt(
      deviceIds: [],
      importedAt: 1,
      importGlobalPreferences: false,
    ),
  ),
  preferencesStatus: .preserved,
);

class _Metadata implements MetadataManagement {
  int previews = 0, imports = 0;
  bool? importGlobal;
  Completer<SettingsImportResult>? pending;
  Future<DeviceMetadata>? exporting;
  void Function()? onImport;
  @override
  Future<DeviceMetadata> exportMetadata() async =>
      exporting ?? DeviceMetadata.parse(_document);
  @override
  Future<SettingsImportPreview> previewImport(DeviceMetadata metadata) async {
    previews++;
    return SettingsImportPreview(
      metadata: metadata,
      expectedRevision: 1,
      newRecords: 0,
    );
  }

  @override
  Future<SettingsImportResult> importMetadata(
    SettingsImportPreview preview, {
    bool importGlobalPreferences = false,
  }) async {
    imports++;
    importGlobal = importGlobalPreferences;
    onImport?.call();
    return pending?.future ?? _result();
  }
}

class _Settings implements SettingsManagement {
  int reads = 0;
  bool failure = false;
  @override
  Future<Preferences> read() async {
    reads++;
    if (failure) throw StateError('settings unavailable');
    return Preferences();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected settings operation');
}

class _Devices implements DeviceReader {
  int reads = 0;
  bool failure = false;
  @override
  Future<List<DeviceSnapshot>> readDevices() async {
    reads++;
    if (failure) throw StateError('devices unavailable');
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected devices operation');
}
