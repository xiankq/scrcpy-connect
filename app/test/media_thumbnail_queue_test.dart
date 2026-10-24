import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/widgets/media_thumbnail.dart';

import 'support/test_controller.dart';

Widget _gallery(
  AppController controller, {
  int count = 8,
  String device = 'a',
  String? provided,
}) => TestProviderScope(
  controller: controller,
  child: MaterialApp(
    home: Scaffold(
      body: Wrap(
        children: [
          for (var i = 0; i < count; i++)
            SizedBox(
              width: 100,
              height: 100,
              child: MediaThumbnail(
                key: ValueKey(i),
                controller: controller,
                device: {'id': device},
                file: {
                  'path': '/$i.jpg',
                  'name': '$i.jpg',
                  'thumbnail': ?provided,
                },
              ),
            ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'eight visible thumbnails share the device decoder without loss',
    (tester) async {
      final requests = <Json>[];
      final pending = <Completer<Json>>[];
      var active = 0;
      var maximum = 0;
      final controller = createTestController((command, [params = const {}]) {
        if (command != 'media.thumbnail') return Future.value({});
        requests.add(Map.of(params));
        active++;
        if (active > maximum) maximum = active;
        final reply = Completer<Json>();
        pending.add(reply);
        return reply.future.whenComplete(() => active--);
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(_gallery(controller));
      await tester.pump();
      expect(maximum, 1, reason: 'the controlled device has one media worker');
      for (var i = 0; i < 8; i++) {
        expect(requests, hasLength(i + 1));
        pending[i].complete({'localPath': '/thumbnail-$i.png'});
        await tester.pump();
      }
      expect(requests.map((p) => p['path']).toSet(), hasLength(8));
      expect(maximum, 1);
      expect(find.byType(Image), findsNWidgets(8));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('leaving cancels only the active lease and drops queued cells', (
    tester,
  ) async {
    final requests = <Json>[];
    final cancellations = <Json>[];
    final pending = Completer<Json>();
    final controller = createTestController((command, [params = const {}]) {
      if (command == 'media.thumbnail') {
        requests.add(Map.of(params));
        return pending.future;
      }
      if (command == 'media.thumbnail.cancel') {
        cancellations.add(Map.of(params));
      }
      return Future.value({});
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(_gallery(controller));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(cancellations, [
      {'deviceId': 'a', 'operationId': requests.single['operationId']},
    ]);
    expect(
      requests.single['operationId'],
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
    pending.complete({'localPath': '/late.png'});
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(requests, hasLength(1));
  });

  testWidgets('busy thumbnails recover with a bounded fresh operation', (
    tester,
  ) async {
    final requests = <Json>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command != 'media.thumbnail') return {};
      requests.add(Map.of(params));
      if (requests.length == 1) throw const RequestFailure('busy', '解码器忙');
      return {'localPath': '/recovered.png'};
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(_gallery(controller, count: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(requests, hasLength(2));
    expect(requests[0]['operationId'], isNot(requests[1]['operationId']));
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'terminal failure explains the thumbnail and offers manual retry',
    (tester) async {
      var calls = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command != 'media.thumbnail') return {};
        calls++;
        if (calls == 1) {
          throw const RequestFailure('permission_denied', '无权读取照片');
        }
        return {'localPath': '/retried.png'};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(_gallery(controller, count: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
      expect(find.textContaining('无权读取照片'), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('重试缩略图')).shortestSide,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byTooltip('重试缩略图'));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('reopening waits for the cancelled request to actually settle', (
    tester,
  ) async {
    final pending = <Completer<Json>>[];
    var active = 0;
    var maximum = 0;
    final controller = createTestController((command, [params = const {}]) {
      if (command != 'media.thumbnail') return Future.value({});
      active++;
      if (active > maximum) maximum = active;
      final reply = Completer<Json>();
      pending.add(reply);
      return reply.future.whenComplete(() => active--);
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(_gallery(controller, count: 1));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(_gallery(controller, count: 1));
    await tester.pump();
    expect(
      pending,
      hasLength(1),
      reason: 'cancel acknowledgement is not completion',
    );
    expect(find.byType(Image), findsNothing);
    pending.first.complete({'localPath': '/old.png'});
    await tester.pump();
    expect(pending, hasLength(2));
    expect(find.byType(Image), findsNothing);
    pending.last.complete({'localPath': '/new.png'});
    await tester.pump();
    expect(maximum, 1);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as ResizeImage)
          .imageProvider,
      isA<FileImage>().having((image) => image.file.path, 'path', '/new.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the same path on another device never shows the old result', (
    tester,
  ) async {
    final requests = <Json>[];
    final pending = <Completer<Json>>[];
    final controller = createTestController((command, [params = const {}]) {
      if (command != 'media.thumbnail') return Future.value({});
      requests.add(Map.of(params));
      final reply = Completer<Json>();
      pending.add(reply);
      return reply.future;
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(_gallery(controller, count: 1));
    await tester.pump();
    await tester.pumpWidget(_gallery(controller, count: 1, device: 'b'));
    await tester.pump();
    expect(requests.map((r) => r['deviceId']), ['a', 'b']);
    expect(requests[0]['operationId'], isNot(requests[1]['operationId']));
    pending[0].complete({'localPath': '/wrong-device.png'});
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    pending[1].complete({'localPath': '/device-b.png'});
    await tester.pump();
    expect(
      (tester.widget<Image>(find.byType(Image)).image as ResizeImage)
          .imageProvider,
      isA<FileImage>().having(
        (image) => image.file.path,
        'path',
        '/device-b.png',
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('persistent busy stops automatic attempts and exposes retry', (
    tester,
  ) async {
    var attempts = 0;
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command != 'media.thumbnail') return {};
      attempts++;
      throw const RequestFailure('busy', '解码器忙，请稍后重试');
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(_gallery(controller, count: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(attempts, 3);
    expect(find.byTooltip('重试缩略图'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(attempts, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('full thumbnail queues explain the bound and allow retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reply = Completer<Json>();
    var requests = 0;
    final controller = createTestController((command, [params = const {}]) {
      if (command != 'media.thumbnail') return Future.value({});
      requests++;
      return reply.future;
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(_gallery(controller, count: 130));
    await tester.pump();
    expect(requests, 1);
    expect(find.textContaining('缩略图等待队列已满'), findsWidgets);
    expect(find.byTooltip('重试缩略图'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    reply.complete({'localPath': '/late.png'});
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(requests, 1);
  });

  testWidgets(
    'provided thumbnails bypass remote work and explain image errors',
    (tester) async {
      var requests = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests++;
        return {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _gallery(controller, count: 1, provided: '/missing-thumbnail.png'),
      );
      await tester.pump();
      expect(requests, 0);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('缩略图无法显示，请重试。'), findsOneWidget);
      expect(find.byTooltip('重试缩略图'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
