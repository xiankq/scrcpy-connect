import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';

import 'support/test_controller.dart';

void main() {
  testWidgets('replacing the controller discards the previous owner results', (
    tester,
  ) async {
    final pending = Completer<Json>();
    final first = createTestController((command, [params = const {}]) async {
      return {'name': 'previous owner'};
    });
    var reads = 0;
    final second = createTestController((command, [params = const {}]) {
      reads++;
      return pending.future;
    });
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Future<void> show(AppController controller) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandView(
            controller: controller,
            command: 'device.info',
            params: const {'deviceId': 'phone'},
            builder: (_, data, _) => Text(value(data, 'name')),
          ),
        ),
      ),
    );

    await show(first);
    await tester.pumpAndSettle();
    expect(find.text('previous owner'), findsOneWidget);
    await show(second);
    expect(reads, 1);
    expect(find.text('previous owner'), findsNothing);
    pending.complete({'name': 'current owner'});
    await tester.pumpAndSettle();
    expect(find.text('current owner'), findsOneWidget);
  });
}
