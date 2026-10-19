import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final lib = Directory('lib');
  test('each product page has its own shallow directory and one page file', () {
    final pages = Directory('${lib.path}/pages');
    final pageFiles = pages
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_page.dart'))
        .toList();
    expect(pageFiles.length, greaterThanOrEqualTo(38));
    final folders = <String>{};
    for (final file in pageFiles) {
      final relative = file.path.substring(pages.path.length + 1).split('/');
      expect(relative, hasLength(2), reason: file.path);
      expect(relative.last, '${relative.first}_page.dart');
      expect(
        folders.add(relative.first),
        isTrue,
        reason: 'Every page owns one directory.',
      );
      final pageClasses = RegExp(
        r'^class (\w+Page)\b',
        multiLine: true,
      ).allMatches(file.readAsStringSync());
      expect(pageClasses, hasLength(1), reason: file.path);
    }
    for (final file
        in lib
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.dart') && !file.path.endsWith('.g.dart'),
            )) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('MaterialPageRoute')), reason: file.path);
      expect(source, isNot(contains('openPage(')), reason: file.path);
      expect(source, isNot(contains('part of ')), reason: file.path);
      expect(
        source,
        isNot(contains("import 'package:scrcpy_connect/features/")),
        reason: file.path,
      );
      for (final match in RegExp(
        r'^class (\w+Page)\b',
        multiLine: true,
      ).allMatches(source)) {
        expect(
          file.path.endsWith('_page.dart'),
          isTrue,
          reason: '${match.group(1)} in ${file.path}',
        );
        expect(
          file.path.startsWith('${pages.path}/'),
          isTrue,
          reason: file.path,
        );
      }
    }
    expect(
      lib
          .listSync()
          .whereType<Directory>()
          .map((directory) => directory.path.split('/').last)
          .toSet(),
      {'pages', 'widgets', 'services', 'router'},
    );
  });

  test(
    'business routes use explicit names and identifier-based record resolution',
    () {
      final routes = File('${lib.path}/router/app_router.dart')
          .readAsStringSync();
      expect(routes, contains('@TypedStatefulShellRoute<HomeShellRoute>'));
      expect(routes, contains("part 'app_router.g.dart'"));
      expect(routes, contains(r'return $appRoutes;'));
      expect(routes, contains('records.device(id)'));
      expect(routes, contains('records.transfer(id)'));
      expect(routes, contains('records.session('));
      expect(routes, isNot(contains("'/page'")));
      expect(routes, isNot(contains('state.extra as Widget')));
      final navigation = File('${lib.path}/router/navigation.dart')
          .readAsStringSync();
      expect(navigation, isNot(contains('/pages/')));
      expect(navigation, isNot(contains('Widget page')));
      expect(navigation, isNot(contains('pushNamed')));
      expect(navigation, contains('RemoteSessionRoute('));
      final state = File('${lib.path}/services/app_controller.dart')
          .readAsStringSync();
      expect(state, contains(r'extends _$AppController'));
      expect(state, isNot(contains('ChangeNotifier')));
      expect(state, contains('ref.onDispose'));
      for (final file
          in Directory('${lib.path}/pages')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('useListenable(controller)')),
          reason: file.path,
        );
      }
      expect(
        File('${lib.path}/app.dart').readAsStringSync(),
        contains('MaterialApp.router('),
      );
    },
  );
}
