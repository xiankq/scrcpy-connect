import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/models/connection_validation.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'support/production_app.dart' show waitFor;

// 经生产应用检查首次配对与撤销；宿主提供隔离的安全 Android 无线调试夹具，不代替应用为此安装的 Rust 身份配对。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var stage = 'waiting-fixture';
  String? runId;
  String? address;
  int? connectPort;
  int? pairPort;
  String? pairingCode;
  var freshCodeReceived = false;
  var connectedCaptured = false;
  var rejectionCaptured = false;
  var revoked = false;
  var fixtureCleaned = false;
  var hostFailed = false;
  binding.reportData = {
    'firstPairingComplete': false,
    'initialUnpairedRejected': false,
    'wrongCodeRejected': false,
    'realPairingCompleted': false,
    'requiredTlsConnected': false,
    'revokedIdentityRejected': false,
    'ownedRecordRemoved': false,
    'fixtureCleanupAcknowledged': false,
  };

  developer.registerExtension('ext.connect.firstPairing', (_, args) async {
    // 不回传载荷、错误文本、配对码或控件截图；宿主失败后仍允许经过认证的清理确认。
    if (args['error'] == 'true') {
      hostFailed = true;
      final failedRun = args['runId'];
      if (runId == null &&
          stage == 'waiting-fixture' &&
          failedRun != null &&
          RegExp(r'^[0-9a-f]{32}$').hasMatch(failedRun)) {
        // 夹具准备失败后仅绑定清理所有权，此错误路径不接收连接数据或凭据。
        runId = failedRun;
      }
    }
    final action = args['action'];
    final incomingRun = args['runId'];
    final incomingPort = int.tryParse(args['pairPort'] ?? '');
    final incomingCode = args['code'];
    bool validPort(int? port) => port != null && port > 0 && port <= 65535;
    bool validCode(String? code) =>
        code != null && RegExp(r'^\d{6}$').hasMatch(code);
    var valid = true;
    switch (action) {
      case 'fixture':
        final incomingConnectPort = int.tryParse(args['connectPort'] ?? '');
        valid =
            stage == 'waiting-fixture' &&
            runId == null &&
            incomingRun != null &&
            RegExp(r'^[0-9a-f]{32}$').hasMatch(incomingRun) &&
            args['address'] == '10.0.2.2' &&
            validPort(incomingConnectPort) &&
            validPort(incomingPort) &&
            incomingConnectPort != incomingPort &&
            validCode(incomingCode);
        if (valid) {
          runId = incomingRun;
          address = args['address'];
          connectPort = incomingConnectPort;
          pairPort = incomingPort;
          pairingCode = incomingCode;
        }
      case 'freshCode':
        valid =
            stage == 'need-fresh-code' &&
            incomingRun == runId &&
            validPort(incomingPort) &&
            incomingPort != connectPort &&
            validCode(incomingCode) &&
            !freshCodeReceived;
        if (valid) {
          pairPort = incomingPort;
          pairingCode = incomingCode;
          freshCodeReceived = true;
        }
      case 'revoked':
        valid = stage == 'need-revoke' && incomingRun == runId;
        if (valid) revoked = true;
      case 'connectedCaptured':
        valid = stage == 'need-connected-capture' && incomingRun == runId;
        if (valid) connectedCaptured = true;
      case 'rejectionCaptured':
        valid = stage == 'revoked-rejected' && incomingRun == runId;
        if (valid) rejectionCaptured = true;
      case 'cleanup':
        valid = stage == 'cleanup' && incomingRun == runId;
        if (valid) fixtureCleaned = true;
      case null:
        break;
      default:
        valid = false;
    }
    if (!valid) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'Invalid first-pairing fixture action or state.',
      );
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage, 'runId': runId}),
    );
  });

  testWidgets('real first pairing, required TLS and identity revocation', (
    tester,
  ) async {
    AppStore? controller;
    final ownedIds = <String>{};
    Set<String>? baselineIds;
    final originalHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;

    void publish(String next) {
      stage = next;
      binding.reportData!['stage'] = next;
    }

    void checkHost() {
      if (hostFailed) {
        throw StateError('The independent first-pairing fixture failed.');
      }
    }

    Future<void> checkpoint(String next, bool Function() ready) async {
      publish(next);
      await waitFor(
        tester,
        () => ready() || hostFailed,
        timeout: const Duration(seconds: 90),
        reason: 'The independent Android fixture must acknowledge $next.',
      );
      checkHost();
    }

    Future<Json> request(String command, [Json params = const {}]) =>
        controller!
            .request(command, params)
            .timeout(const Duration(seconds: 75));

    final page = find.byType(ConnectionFormPage);
    Finder field(String label) => find.descendant(
      of: page,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    );

    Future<void> fill(String label, String text) async {
      final target = field(label);
      expect(target, findsOneWidget);
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(target);
      await tester.enterText(target, text);
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> waitForForm({bool pairing = false, String? deviceId}) async {
      await waitFor(
        tester,
        () =>
            page.evaluate().length == 1 &&
            tester.widget<ConnectionFormPage>(page).pairing == pairing &&
            tester.widget<ConnectionFormPage>(page).deviceId == deviceId &&
            ModalRoute.of(tester.element(page))?.animation?.status ==
                AnimationStatus.completed,
        reason: 'The production route must show the expected connection form.',
      );
    }

    Future<void> openForm({bool pairing = false, String? deviceId}) async {
      ConnectionFormRoute(
        pairing: pairing,
        deviceId: deviceId,
        transport: ConnectionTransport.tls,
      ).go(tester.element(find.byType(Scaffold).first));
      await tester.pump();
      await waitForForm(pairing: pairing, deviceId: deviceId);
      await fill('IP 地址或主机名', address!);
    }

    Future<void> submit({bool pairing = false}) async {
      final button = find.descendant(
        of: page,
        matching: find.widgetWithText(
          FilledButton,
          pairing ? '配对并检查连接' : '连接设备',
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.ensureVisible(button);
      await tester.pump(const Duration(milliseconds: 200));
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 200));
    }

    List<String> formErrors() => tester
        .widgetList<StateNote>(
          find.descendant(of: page, matching: find.byType(StateNote)),
        )
        .map((note) => note.message)
        .where((message) => !message.startsWith('跨网连接需要已有可达网络'))
        .toList();

    Future<void> waitForFormRejection() => waitFor(
      tester,
      () =>
          formErrors().isNotEmpty &&
          find
              .descendant(
                of: page,
                matching: find.byType(CircularProgressIndicator),
              )
              .evaluate()
              .isEmpty,
      timeout: const Duration(seconds: 75),
      reason: 'The real submitted request must finish with a form error.',
    );

    bool authRejection(String reason) {
      final lower = reason.toLowerCase();
      return lower.contains('authorization is required') ||
          lower.contains('certificaterequired') ||
          lower.contains('badcertificate') ||
          lower.contains('unknownca') ||
          lower.contains('certificateunknown') ||
          lower.contains('accessdenied') ||
          lower.contains('certificate required') ||
          lower.contains('bad certificate') ||
          lower.contains('unknown ca');
    }

    Future<Json> record(String id) => request('device.info', {'deviceId': id});

    void assertAuthorizationFeedback() {
      expect(formErrors().single, contains('被控设备未信任此主控的授权身份'));
      expect(
        find.descendant(of: page, matching: find.text('重新配对')),
        findsOneWidget,
      );
    }

    Future<void> assertAuthRejection(String id, String reportKey) async {
      final device = await record(id);
      expect(device['transport'], 'tls');
      expect(device['status'], 'unauthorized');
      expect(device['autoReconnect'], isFalse);
      final reason = value(device, 'reason');
      expect(
        authRejection(reason),
        isTrue,
        reason:
            'The real device reason must identify authorization or TLS '
            'certificate rejection; generic network failures do not qualify. '
            'Actual reason: $reason',
      );
      binding.reportData![reportKey] = true;
      binding.reportData!['${reportKey}Reason'] = reason;
    }

    Future<void> collectOwnedRecords() async {
      final baseline = baselineIds;
      if (controller == null || baseline == null) return;
      final devices = objects((await request('devices.list'))['devices']);
      for (final device in devices) {
        final id = value(device, 'id');
        // 配对期间明确保留初始表单创建的唯一记录，绝不删除测试前已存在的记录。
        if (!baseline.contains(id) &&
            device['address'] == address &&
            device['port'] == connectPort &&
            device['transport'] == 'tls') {
          ownedIds.add(id);
        }
      }
    }

    try {
      await app.main();
      await waitFor(
        tester,
        () => find.byTooltip('添加设备').evaluate().isNotEmpty,
        reason:
            'The production bootstrap must finish with its real Rust bridge.',
      );
      controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appStoreProvider.notifier);
      baselineIds = objects((await request('devices.list'))['devices'])
          .map((device) => value(device, 'id'))
          .toSet();
      await checkpoint('waiting-fixture', () => runId != null);
      binding.reportData!['fixtureRunId'] = runId;

      await openForm();
      await fill('连接端口', '$connectPort');
      await submit();
      await waitForFormRejection();
      await collectOwnedRecords();
      expect(
        ownedIds.length,
        1,
        reason: 'The initial form must create exactly one owned record.',
      );
      final deviceId = ownedIds.single;
      expect((await record(deviceId))['guid'], isNull);
      await assertAuthRejection(deviceId, 'initialUnpairedRejected');
      assertAuthorizationFeedback();
      publish('initial-rejected');
      await tester.pump(const Duration(seconds: 1));

      final repair = find.descendant(
        of: page,
        matching: find.widgetWithText(TextButton, '重新配对'),
      );
      await tester.ensureVisible(repair);
      await tester.pump(const Duration(milliseconds: 200));
      expect(repair.hitTestable(), findsOneWidget);
      await tester.tap(repair);
      await tester.pump();
      await waitForForm(pairing: true, deviceId: deviceId);
      expect(
        tester.widget<TextField>(field('IP 地址或主机名')).controller!.text,
        address,
      );
      expect(tester.widget<TextField>(field('配对端口')).controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(field('配对码')).controller!.text.isEmpty,
        true,
      );
      await fill('配对端口', '$pairPort');
      // 仅修改当前有效配对码的一位；两份值都不进入报告、诊断、扩展响应或截图。
      final code = pairingCode!;
      final wrongCode = '${(int.parse(code[0]) + 1) % 10}${code.substring(1)}';
      await fill('配对码', wrongCode);
      await submit(pairing: true);
      await waitForFormRejection();
      expect((await record(deviceId))['guid'], isNull);
      final failure = tester
          .widget<ConnectionFailureNote>(
            find.descendant(
              of: page,
              matching: find.byType(ConnectionFailureNote),
            ),
          )
          .failure;
      expect(
        failure is RequestFailure,
        isTrue,
        reason: 'The real pairing request must return a structured failure.',
      );
      // 实际对端故障与本地化呈现分开；原始故障和当前配对码仅留内存，不进入报告。
      final requestFailure = failure as RequestFailure;
      final wrongError = requestFailure.message.toLowerCase();
      final authenticationFailed = wrongError.contains(
        'pairing authentication failed',
      );
      expect(
        authenticationFailed ||
            wrongError.contains('unexpected end of file') ||
            wrongError.contains('unexpected eof') ||
            wrongError.contains('early eof') ||
            wrongError.contains(
              'peer closed connection without sending tls close_notify',
            ) ||
            wrongError.contains('connection reset by peer') ||
            wrongError.contains('failed to fill whole buffer'),
        isTrue,
        reason:
            'The wrong six-digit code must reach the real pairing peer '
            'and fail authentication or be closed by that peer.',
      );
      final String expectedFeedback;
      if (authenticationFailed) {
        expectedFeedback = '配对验证未通过。请确认正在使用被控手机当前配对窗口的端口和配对码，重新打开配对窗口后重试。';
      } else if (requestFailure.code == 'disconnected' ||
          RegExp(r'\b(eof|end of file)\b').hasMatch(wrongError)) {
        expectedFeedback = '配对连接在完成前中断，暂时无法确认原因。请确认被控手机的配对窗口仍开启、网络可达；需要重试时，重新打开配对窗口并填写当前端口和配对码。';
      } else {
        throw StateError(
          'The pairing peer failure needs its own localized feedback assertion.',
        );
      }
      expect(formErrors(), [expectedFeedback]);
      expect(formErrors().single, isNot(contains('码错误')));
      expect(
        find.descendant(of: page, matching: find.text('已配对，正在确认连接')),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(field('配对码')).controller!.text.isEmpty,
        true,
      );
      binding.reportData!['wrongCodeRejected'] = true;
      pairingCode = null;
      await checkpoint('need-fresh-code', () => freshCodeReceived);

      await fill('配对端口', '$pairPort');
      await fill('配对码', pairingCode!);
      await submit(pairing: true);
      await waitFor(
        tester,
        () =>
            find.byType(DeviceWorkspacePage).evaluate().isNotEmpty ||
            (find
                    .descendant(of: page, matching: find.text('已配对，正在确认连接'))
                    .evaluate()
                    .isNotEmpty &&
                find
                    .descendant(
                      of: page,
                      matching: find.byType(CircularProgressIndicator),
                    )
                    .evaluate()
                    .isEmpty),
        timeout: const Duration(seconds: 75),
        reason: 'The real pairing form must complete, with or without automatic discovery.',
      );
      final paired = await record(deviceId);
      expect(value(paired, 'guid'), isNotEmpty);
      expect(paired['transport'], 'tls');
      binding.reportData!['realPairingCompleted'] = true;
      pairingCode = null;
      if (page.evaluate().isNotEmpty) await fill('配对码', '');
      publish('paired');
      await tester.pump(const Duration(seconds: 1));

      // 发现可能已连接；先明确断开，再在真实表单输入独立宿主转发的连接端口。
      await request('devices.disconnect', {'deviceId': deviceId});
      await openForm(deviceId: deviceId);
      await fill('连接端口', '$connectPort');
      await submit();
      await waitFor(
        tester,
        () => find.byType(DeviceWorkspacePage).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 75),
        reason: 'The explicit connection port must establish the paired TLS connection.',
      );
      final connected = await record(deviceId);
      expect(connected['status'], 'connected');
      expect(connected['transport'], 'tls');
      expect(connected['port'], connectPort);
      expect(value(connected, 'guid'), isNotEmpty);
      final capabilities = objects(
        (await request('device.capabilities', {
          'deviceId': deviceId,
        }))['capabilities'],
      );
      expect(
        capabilities.singleWhere((item) => item['key'] == 'shell')['status'],
        'available',
      );
      expect(
        capabilities.singleWhere((item) => item['key'] == 'files')['status'],
        'available',
      );
      binding.reportData!['requiredTlsConnected'] = true;
      await checkpoint('need-connected-capture', () => connectedCaptured);
      await request('devices.disconnect', {'deviceId': deviceId});
      expect((await record(deviceId))['status'], 'offline');
      await checkpoint('need-revoke', () => revoked);

      await openForm(deviceId: deviceId);
      await fill('连接端口', '$connectPort');
      await submit();
      await waitForFormRejection();
      await assertAuthRejection(deviceId, 'revokedIdentityRejected');
      assertAuthorizationFeedback();
      await tester.ensureVisible(
        find.descendant(of: page, matching: find.byType(ConnectionFailureNote)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await checkpoint('revoked-rejected', () => rejectionCaptured);
      expect(tester.takeException(), isNull);
    } catch (error, stack) {
      binding.reportData!['failedStage'] = stage;
      binding.reportData!['failureType'] = '${error.runtimeType}';
      // 独立清理也失败时，堆栈位置帮助保留首要故障；异常文本可能包含输入，因此省略。
      binding.reportData!['failureLocations'] = stack
          .toString()
          .split('\n')
          .where((line) => line.contains('first_pairing_test.dart'))
          .take(3)
          .toList();
      rethrow;
    } finally {
      pairingCode = null;
      try {
        // 宿主清理失败不能跳过删除本测试记录。
        publish('cleanup');
        await waitFor(
          tester,
          () => fixtureCleaned,
          timeout: const Duration(seconds: 90),
          reason: 'The host must remove this run\'s exact trust entry and forwards.',
        );
        binding.reportData!['fixtureCleanupAcknowledged'] = true;
      } finally {
        try {
          Object? cleanupError;
          StackTrace? cleanupStack;
          void retainError(Object error, StackTrace stack) {
            cleanupError ??= error;
            cleanupStack ??= stack;
          }

          try {
            await collectOwnedRecords();
          } catch (error, stack) {
            retainError(error, stack);
          }
          for (final id in ownedIds) {
            try {
              expect(baselineIds!.contains(id), isFalse);
              await request('devices.forget', {'deviceId': id});
            } catch (error, stack) {
              retainError(error, stack);
            }
          }
          if (controller != null && baselineIds != null) {
            final remaining = objects(
              (await request('devices.list'))['devices'],
            ).map((device) => value(device, 'id')).toSet();
            expect(remaining.intersection(ownedIds), isEmpty);
            expect(remaining.containsAll(baselineIds), isTrue);
            binding.reportData!['ownedRecordRemoved'] = ownedIds.isNotEmpty;
          }
          if (cleanupError != null) {
            Error.throwWithStackTrace(cleanupError!, cleanupStack!);
          }
        } finally {
          WidgetController.hitTestWarningShouldBeFatal = originalHitTestPolicy;
          publish('done');
        }
      }
    }
    const requiredResults = [
      'initialUnpairedRejected',
      'wrongCodeRejected',
      'realPairingCompleted',
      'requiredTlsConnected',
      'revokedIdentityRejected',
      'ownedRecordRemoved',
      'fixtureCleanupAcknowledged',
    ];
    for (final key in requiredResults) {
      expect(
        binding.reportData![key],
        isTrue,
        reason: '$key requires real evidence.',
      );
    }
    binding.reportData!['firstPairingComplete'] = true;
  });
}
