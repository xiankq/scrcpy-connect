import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/transfers/details/index/transfers_details_index_page.dart';
import 'package:scrcpy_connect/pages/transfers/index/transfers_index_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'backend export refusal prevents a partial directory from appearing saved as a complete tree',
    (tester) async {
      final task = <String, dynamic>{
        'id': 'directory',
        'name': 'Documents',
        'kind': 'directory',
        'direction': 'pull',
        'status': 'completed',
        'treeVerified': true,
        'treeComplete': false,
        'canExport': false,
        'exportReason': '目录存在失败项目，请先核对。',
        'destination': '/cache/Documents',
        'destinationScope': 'privateCache',
      };
      final controller = createTestController(
        (command, [params = const {}]) async =>
            command == 'transfers.get' ? task : {},
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: TransferDetailsPage(controller: controller, task: task),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('目录存在失败项目，请先核对。'), findsOneWidget);
      expect(find.text('文件夹结构已取回。保存到系统位置后，可在文件应用中查看。'), findsNothing);
      expect(find.text('已完成'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'a directory is not presented as complete while its source tree is still being verified',
    (tester) async {
      final task = <String, dynamic>{
        'id': 'directory',
        'name': 'Documents',
        'kind': 'directory',
        'direction': 'pull',
        'status': 'completed',
        'treeVerified': false,
        'destinationScope': 'privateCache',
        'destination': '/cache/Documents',
      };
      final controller = createTestController(
        (command, [params = const {}]) async =>
            command == 'transfers.get' ? task : {},
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: TransferDetailsPage(controller: controller, task: task),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('目录结构已建立，仍在核验所选内容。请等待批次实际结果。'), findsOneWidget);
      expect(find.text('已完成'), findsNothing);
      expect(find.textContaining('已保存至'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'per-item cancellation follows backend capability even for queued work',
    (tester) async {
      var task = <String, dynamic>{
        'id': 'queued',
        'name': 'Queued file',
        'status': 'queued',
        'canCancel': true,
      };
      Json? cancelled;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'transfers.get') return task;
        if (command == 'transfers.cancel') cancelled = params;
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: TransferDetailsPage(controller: controller, task: task),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消传输'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消传输').last);
      await tester.pumpAndSettle();
      expect(cancelled, {'transferId': 'queued'});
      task = {...task, 'status': 'finalizing', 'canCancel': false};
      controller.eventRevision++;
      await controller.loadSettings();
      await tester.pumpAndSettle();
      expect(find.text('取消传输'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'a completed directory is not offered to file-only sharing or open APIs',
    (tester) async {
      final task = <String, dynamic>{
        'id': 'directory',
        'name': 'Empty folder',
        'kind': 'directory',
        'treeVerified': true,
        'canExport': true,
        'direction': 'pull',
        'status': 'completed',
        'destination': '/tmp/Empty folder',
      };
      final controller = createTestController(
        (command, [params = const {}]) async =>
            command == 'transfers.get' ? task : {},
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: TransferDetailsPage(controller: controller, task: task),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('文件夹结构已取回，请在保存位置查看。'), findsOneWidget);
      expect(find.text('系统分享'), findsNothing);
      expect(find.text('用本机应用打开'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'directory batches show actual counts and cancel the entire selected batch only when permitted',
    (tester) async {
      Json? cancelled;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'transfers.cancel') cancelled = params;
        if (command == 'transfers.list') {
          return {
            'transfers': [
              {
                'id': 'folder',
                'batchId': 'batch-a',
                'name': 'Documents',
                'kind': 'directory',
                'status': 'completed',
                'direction': 'push',
                'total': 0,
              },
            ],
            'batches': [
              {
                'batchId': 'batch-a',
                'direction': 'push',
                'status': 'conflict',
                'fileCount': 2,
                'directoryCount': 1,
                'completed': 1,
                'itemCount': 3,
                'transferred': 4,
                'total': 10,
                'canCancel': true,
              },
              {
                'batchId': 'batch-b',
                'direction': 'pull',
                'status': 'completedWithSkips',
                'fileCount': 1,
                'directoryCount': 0,
                'completed': 0,
                'skipped': 1,
                'itemCount': 1,
                'canCancel': false,
              },
            ],
          };
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: TransfersPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 个文件 · 1 个文件夹'), findsOneWidget);
      expect(find.text('部分内容已跳过'), findsOneWidget);
      expect(find.text('取消本批传输'), findsOneWidget);
      await tester.tap(find.text('取消本批传输'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消传输').last);
      await tester.pumpAndSettle();
      expect(cancelled, {'batchId': 'batch-a'});
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'retry is explicit restart from zero and unknown results cannot retry',
    (tester) async {
      Json? restart;
      var task = <String, dynamic>{
        'id': 'transfer',
        'status': 'failed',
        'canResume': false,
        'canRestart': true,
        'name': 'document.pdf',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'transfers.get') return task;
        if (command == 'transfers.resume') restart = params;
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: TransferDetailsPage(controller: controller, task: task),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('重新传输'));
      await tester.tap(find.text('重新传输'));
      await tester.pumpAndSettle();
      expect(find.text('从头重新传输？'), findsOneWidget);
      await tester.tap(find.text('重新传输').last);
      await tester.pumpAndSettle();
      expect(restart, {'transferId': 'transfer', 'restart': true});
      task = {...task, 'canRestart': false, 'errorCode': 'result_unknown'};
      controller.eventRevision++;
      await controller.loadSettings();
      await tester.pumpAndSettle();
      expect(find.text('重新传输'), findsNothing);
      expect(find.text('检查并继续'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
