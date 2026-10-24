import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/receive/transfers_details_receive_page.dart';
import 'package:scrcpy_connect/pages/transfers/details/index/transfers_details_index_page.dart';
import 'package:scrcpy_connect/widgets/media_thumbnail.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final receive in [true, false]) {
    testWidgets(
      'a ${receive ? 'receive' : 'details'} status page releases its preparation lease after interruption',
      (tester) async {
        var status = 'running';
        final released = <String>[];
        const task = {
          'id': 'transfer-a',
          'deviceId': 'a',
          'direction': 'pull',
          'destinationScope': 'privateCache',
          'name': '原件',
          'status': 'running',
        };
        final events = StreamController<Json>.broadcast(sync: true);
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command == 'transfers.get') return {...task, 'status': status};
          if (command == 'media.cache.acquire') {
            return {'leaseId': 'preparation-lease'};
          }
          if (command == 'media.cache.release') {
            released.add(params['leaseId'] as String);
          }
          return {};
        }, events: events.stream);
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: receive
                ? ReceiveContentPage(controller: controller, task: task)
                : TransferDetailsPage(controller: controller, task: task),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(released, isEmpty);
        status = 'interrupted';
        events.add({'type': 'transfers.changed', 'transferId': task['id']});
        await tester.pumpAndSettle();
        expect(
          released,
          ['preparation-lease'],
          reason: 'A status-only page must not block explicit restart with its own lease.',
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      },
    );
  }
  for (final thumbnail in [true, false]) {
    testWidgets(
      'a late ${thumbnail ? 'thumbnail' : 'preview'} releases only its returned cache lease',
      (tester) async {
        final response = Completer<Json>();
        final released = <Json>[];
        final command = thumbnail ? 'media.thumbnail' : 'media.preview';
        final controller = createTestController((
          name, [
          params = const {},
        ]) async {
          if (name == command) return response.future;
          if (name == 'media.cache.release') released.add(Map.of(params));
          return {};
        });
        const device = {'id': 'a', 'name': '手机 A'};
        const file = {'path': '/a.jpg', 'name': 'a.jpg', 'mime': 'image/jpeg'};
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: thumbnail
                ? SizedBox(
                    width: 100,
                    height: 100,
                    child: MediaThumbnail(
                      controller: controller,
                      device: device,
                      file: file,
                    ),
                  )
                : MediaPreviewPage(
                    controller: controller,
                    device: device,
                    file: file,
                  ),
          ),
        );
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        response.complete({
          'localPath': '/a.jpg',
          'cacheLeaseId': 'owned-late-lease',
        });
        await tester.pump();
        await tester.pump();
        expect(released, [
          {'leaseId': 'owned-late-lease'},
        ]);
        controller.dispose();
      },
    );
  }
}
