import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/app_settings.dart';
import 'package:scrcpy_connect/models/device_metadata.dart';
import 'package:scrcpy_connect/stores/connection/device_record_store.dart';

void main() {
  test('导入真实提交回执未知后保留恢复结果，重开核验不重复恢复设备', () async {
    final directory = await Directory.systemTemp.createTemp('import-unknown-');
    addTearDown(() => directory.delete(recursive: true));
    final preferences = await AppSettings.prepare(directory);
    var imports = 0, publications = 0;
    final document = {
      'format': 'scrcpy-connect-metadata',
      'version': 1,
      'devices': [
        {
          'name': '恢复设备',
          'address': '192.0.2.1',
          'port': 5555,
          'transport': 'tcp',
        },
      ],
      'settings': {'appearance': 'dark'},
    };
    final fingerprint = DeviceMetadata.parse(document).fingerprint;
    final records = await DeviceRecordStore.open(
      directory: directory,
      idFactory: () {
        imports++;
        return '11111111-1111-4111-8111-111111111111';
      },
    );
    final commands = AppSettings(
      preferences: preferences,
      records: records,
      onDevicesImported: (_) {},
      onChanged: (_) => publications++,
    );
    final faults = _LostPreferenceCommit(
      File.fromUri(directory.uri.resolve('preferences.json')).path,
    );
    await IOOverrides.runWithIOOverrides(() async {
      await expectLater(
        commands.importMetadata({
          'metadata': document,
          'fingerprint': fingerprint,
          'importGlobalPreferences': true,
        }),
        throwsA(
          isA<RequestFailure>()
              .having(
                (error) => error.code,
                'code',
                'preferences_import_unknown',
              )
              .having(
                (error) => error.details,
                'details',
                allOf(
                  containsPair('preferencesSaved', 'unknown'),
                  containsPair('devicesRestored', containsPair('restored', 1)),
                  containsPair('authorizationRestored', false),
                  containsPair('cause', 'preferences_write_unknown'),
                ),
              ),
        ),
      );
    }, faults);
    expect(faults.committed, isTrue);
    expect(faults.verificationFailed, isTrue);
    expect(imports, 1);
    expect(publications, 0);
    // 存储确已提交，旧内存仍保持未知提交前的快照；必须读取而非再次导入。
    expect(preferences.current.values['appearance'], 'light');
    final reopened = await AppSettings.prepare(directory);
    expect(reopened.current.values['appearance'], 'dark');
    await commands.reconcile();
    expect(commands.settings['appearance'], 'dark');
    expect(imports, 1);
    expect(publications, 1);
    final checked = await commands.previewImport({'metadata': document}) as Map;
    expect(checked['alreadyImported'], true);
    expect(checked['preferencesStatus'], 'matchesCurrent');
    expect(checked['newRecords'], 0);
    expect(records.current.devices, hasLength(1));
    expect(imports, 1);
  });
}

/// 文件内容、flush 和 rename 均真实执行；仅模拟提交后的系统回执及核验读失败。
final class _LostPreferenceCommit extends IOOverrides {
  _LostPreferenceCommit(this.preferencePath);
  final String preferencePath;
  bool committed = false, verificationFailed = false;

  @override
  File createFile(String path) => _FaultFile(super.createFile(path), this);
}

final class _FaultFile implements File {
  _FaultFile(this.file, this.faults);
  final File file;
  final _LostPreferenceCommit faults;
  @override
  String get path => file.path;

  @override
  Future<int> length() => file.length();

  @override
  Future<bool> exists() => file.exists();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);

  @override
  Future<File> rename(String newPath) async {
    final installed = await file.rename(newPath);
    if (newPath == faults.preferencePath && !faults.committed) {
      faults.committed = true;
      throw const FileSystemException('提交已完成，但系统替换回执丢失');
    }
    return installed;
  }

  @override
  Future<Uint8List> readAsBytes() {
    if (path == faults.preferencePath &&
        faults.committed &&
        !faults.verificationFailed) {
      faults.verificationFailed = true;
      throw const FileSystemException('系统暂时无法读取已提交目标以核验');
    }
    return file.readAsBytes();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
