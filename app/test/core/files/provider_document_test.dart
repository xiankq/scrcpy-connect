import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/models/provider_document.dart';

void main() {
  test('目录内容或分页标记异常时拒绝响应，不将其视为空目录', () {
    for (final page in [
      {'documents': null, 'hasMore': false, 'loading': false},
      {
        'documents': [_file, null],
        'hasMore': false,
        'loading': false,
      },
      {
        'documents': [_file, 42],
        'hasMore': false,
        'loading': false,
      },
      {'documents': <Object?>[], 'loading': false},
      {'documents': <Object?>[], 'hasMore': 'false', 'loading': false},
      {
        'documents': [
          {..._file, 'directory': 'false'},
        ],
        'hasMore': false,
        'loading': false,
      },
    ]) {
      expect(
        () => ProviderDocumentPage.fromJson(page),
        throwsA(
          isA<RequestFailure>().having(
            (e) => e.code,
            '拒绝异常',
            'invalid_document_response',
          ),
        ),
      );
    }
  });

  test('有效分页保留未知长度与能力声明，快照不受原响应修改影响', () {
    final row = {..._file};
    final entries = [row];
    final page = ProviderDocumentPage.fromJson({
      'documents': entries,
      'hasMore': true,
      'loading': false,
    });
    row['name'] = '被替换';
    entries.clear();
    expect(page.documents.single.name, '原文件');
    expect(page.documents.single.size, isNull);
    expect(page.documents.single.canWrite, isFalse);
    expect(page.hasMore, isTrue);
    expect(() => page.documents.clear(), throwsUnsupportedError);
  });
}

const _file = <String, Object?>{
  'handle': 'handle',
  'uri': 'content://provider/file',
  'authority': 'provider',
  'id': 'file',
  'name': '原文件',
  'directory': false,
  'virtual': false,
  'canWrite': false,
  'canCreate': false,
  'size': null,
  'modified': null,
};
