import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/file_document_service.dart';
import 'package:scrcpy_connect/core/files/file_selection_requests.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';

void main() {
  final pages = <String, Map<String, dynamic>>{
    '缺少目录列表': {'hasMore': false, 'loading': false},
    '混入无效项目': {
      'documents': [_folder, null],
      'hasMore': false,
      'loading': false,
    },
    '有效空目录': {'documents': <Object?>[], 'hasMore': false, 'loading': false},
  };
  for (final entry in pages.entries) {
    test('${entry.key}只在确认为有效空目录时完成导入，结束后释放原操作', () async {
      final cache = await Directory.systemTemp.createTemp('document-provider-');
      addTearDown(() => cache.delete(recursive: true));
      final native = _Scopes();
      final files = LocalFiles(native);
      addTearDown(files.close);
      late FileSelectionRequests selections;
      selections = FileSelectionRequests((request) {
        selections.complete(
          request.operationId,
          DocumentLocationsSelected([
            const SelectedDocument(
              handle: 'folder',
              uri: 'content://provider/folder',
            ),
          ]),
        );
      });
      var releases = 0;
      final service = FileDocumentService(
        files: () async => files,
        platform: (command, params) async {
          switch (command) {
            case 'documents.platform.environment':
              return {'cacheDirectory': cache.path, 'ownerLeaseId': 'owner'};
            case 'documents.platform.metadata':
              return _folder;
            case 'documents.platform.children':
              return entry.value;
            case 'documents.platform.release':
              expect(params['ownerLeaseId'], 'owner');
              expect(native.active, 0);
              releases++;
              return {'released': true};
            default:
              throw StateError('不应调用 $command');
          }
        },
        selections: selections,
      );
      addTearDown(service.dispose);
      final result = await service.importDocuments('import', .directory);
      if (entry.key == '有效空目录') {
        expect(result.status, DocumentOutcomeStatus.imported);
        expect(result.errors, isEmpty);
      } else {
        expect(result.status, DocumentOutcomeStatus.partial);
        expect(result.errors.single.code, 'invalid_document_response');
      }
      expect(result.directories, 1);
      expect(releases, 1);
      expect(native.active, 0);
    });
  }
}

const _folder = <String, dynamic>{
  'handle': 'folder',
  'uri': 'content://provider/folder',
  'authority': 'provider',
  'id': 'folder',
  'name': '文件夹',
  'directory': true,
  'virtual': false,
  'canCreate': true,
  'canWrite': false,
  'size': null,
  'modified': null,
};

final class _Scopes implements NativeLocalFilesApi {
  var active = 0;
  @override
  Future<String> openScope(
    String key,
    List<Uint8List> roots,
    int timeout,
  ) async {
    active++;
    return 'scope';
  }

  @override
  Future<void> closeScope(String id, int timeout) async {
    active--;
  }

  @override
  Future<void> mkdir(String id, Uint8List path, bool exclusive) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('未预期的文档读取：${invocation.memberName}');
}
