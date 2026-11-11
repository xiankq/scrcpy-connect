import 'dart:async';

import 'package:scrcpy_connect/models/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/transfers/details/index/transfers_details_index_page.dart';
import 'package:scrcpy_connect/pages/transfers/index/transfers_index_page.dart';
import 'package:scrcpy_connect/pages/transfers/index/widgets/transfer_history_row.dart';

import 'support/router_test_app.dart';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      final events = StreamController<Json>.broadcast(sync: true);
      final controller = createTestController((command, params) async {
        if (command == 'transfers.get') return task;
        if (command == 'transfers.cancel') cancelled = params;
        return {};
      }, events: events.stream);
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
      events.add({'type': 'transfers.changed', 'transferId': task['id']});
      await tester.pumpAndSettle();
      expect(find.text('取消传输'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
  testWidgets(
    'conflict details show the actual source and destination paths with the three policies',
    (tester) async {
      final task = <String, dynamic>{
        'id': 'conflict',
        'deviceId': 'phone',
        'batchId': 'batch',
        'name': '旅行照片',
        'kind': 'directory',
        'direction': 'pull',
        'status': 'conflict',
        'itemCount': 2,
        'sourceLabel': '我的手机',
        'destinationLabel': '本机暂存',
        'destinationScope': 'privateCache',
        'source': '/sdcard/DCIM/旅行照片.jpg',
        'destination': '/cache/旅行照片.jpg',
        'batch': {
          'batchId': 'batch',
          'status': 'conflict',
          'itemCount': 2,
          'canCancel': true,
        },
        'items': [
          {
            'id': 'conflict',
            'name': '旅行照片.jpg',
            'kind': 'file',
            'direction': 'pull',
            'status': 'conflict',
            'source': '/sdcard/DCIM/旅行照片.jpg',
            'destination': '/cache/旅行照片.jpg',
          },
          {
            'id': 'other',
            'name': '清单.pdf',
            'kind': 'file',
            'direction': 'pull',
            'status': 'completed',
          },
        ],
      };
      Json? resolved;
      final controller =
          createTestController((command, params) async {
              if (command == 'transfers.get') return task;
              if (command == 'transfers.resolve') resolved = params;
              return {};
            })
            ..devices = [
              {'id': 'phone', 'name': '我的手机', 'status': 'connected'},
            ];
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: TransferDetailsPage(controller: controller, task: task),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('旅行照片.jpg'), findsNWidgets(2));
      expect(find.text('来源 · 我的手机\n/sdcard/DCIM/旅行照片.jpg'), findsOneWidget);
      expect(find.text('目标 · 本机暂存\n/cache/旅行照片.jpg'), findsOneWidget);
      expect(find.text('替换将覆盖目标中的同名文件。'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '保留两份'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '替换目标文件'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '跳过此项'), findsOneWidget);
      await tester.tap(find.text('保留两份'));
      await tester.pumpAndSettle();
      expect(resolved, {
        'transferId': 'conflict',
        'policy': 'keepBoth',
        'applyToAll': false,
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'compact history groups batch children and stops before removing only the confirmed batch',
    (tester) async {
      final requests = <(String, Json)>[];
      var stopped = false;
      var removed = false;
      final controller = createTestController((command, params) async {
        requests.add((command, params));
        if (command == 'transfers.cancel') stopped = true;
        if (command == 'transfers.remove') removed = true;
        if (command == 'transfers.list') {
          return {
            'transfers': [
              if (!removed) ...[
                {
                  'id': 'folder',
                  'batchId': 'batch-a',
                  'name': 'Documents',
                  'kind': 'directory',
                  'status': stopped ? 'cancelled' : 'running',
                  'direction': 'push',
                  'treeVerified': true,
                },
                {
                  'id': 'child',
                  'parentId': 'folder',
                  'batchId': 'batch-a',
                  'name': 'child.pdf',
                  'status': stopped ? 'cancelled' : 'conflict',
                  'direction': 'push',
                },
              ],
              {
                'id': 'other',
                'batchId': 'batch-b',
                'name': 'Other.pdf',
                'status': 'completed',
                'direction': 'pull',
              },
            ],
            'batches': [
              {
                'batchId': 'batch-a',
                'status': stopped ? 'cancelled' : 'conflict',
                'canCancel': !stopped,
                'transferred': 4,
                'total': 10,
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
      expect(find.byType(TransferHistoryRow), findsNWidgets(2));
      expect(find.text('child.pdf'), findsNothing);
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('最近'), findsOneWidget);
      expect(find.text('发送 · 本机 → 设备'), findsOneWidget);
      expect(find.text('接收 · 设备'), findsOneWidget);
      expect(
        tester.getSize(find.byType(TransferHistoryRow).first).height,
        lessThanOrEqualTo(128),
      );
      await tester.tap(find.byTooltip('传输操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止并移除…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        requests.where(
          (r) => r.$1 == 'transfers.cancel' || r.$1 == 'transfers.remove',
        ),
        isEmpty,
      );
      await tester.tap(find.byTooltip('传输操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止并移除…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止并移除'));
      await tester.pumpAndSettle();
      final mutations = requests
          .where(
            (r) => r.$1 == 'transfers.cancel' || r.$1 == 'transfers.remove',
          )
          .toList();
      expect(mutations.map((r) => r.$1), [
        'transfers.cancel',
        'transfers.remove',
      ]);
      expect(mutations.map((r) => r.$2), [
        {'batchId': 'batch-a'},
        {'batchId': 'batch-a'},
      ]);
      expect(find.text('Documents'), findsNothing);
      expect(find.text('Other.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'finished history removal is confirmed and never deletes the saved file',
    (tester) async {
      final requests = <(String, Json)>[];
      var removed = false;
      final controller = createTestController((command, params) async {
        requests.add((command, params));
        if (command == 'transfers.remove') removed = true;
        if (command == 'transfers.list') {
          return {
            'transfers': [
              if (!removed)
                {
                  'id': 'saved',
                  'name': 'Saved.pdf',
                  'direction': 'pull',
                  'status': 'completed',
                  'destinationScope': 'system',
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
      await tester.tap(find.byTooltip('传输操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除记录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不会删除已保存文件'), findsOneWidget);
      expect(requests.where((r) => r.$1 == 'transfers.remove'), isEmpty);
      await tester.tap(find.text('移除记录').last);
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'transfers.remove').single.$2, {
        'transferId': 'saved',
      });
      expect(
        requests.where(
          (r) => r.$1 == 'transfers.cancel' || r.$1.startsWith('files.'),
        ),
        isEmpty,
      );
      expect(find.text('暂无传输'), findsOneWidget);
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
      final events = StreamController<Json>.broadcast(sync: true);
      final controller = createTestController((command, params) async {
        if (command == 'transfers.get') return task;
        if (command == 'transfers.resume') restart = params;
        return {};
      }, events: events.stream);
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
      events.add({'type': 'transfers.changed', 'transferId': task['id']});
      await tester.pumpAndSettle();
      expect(find.text('重新传输'), findsNothing);
      expect(find.text('检查并继续'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
}
