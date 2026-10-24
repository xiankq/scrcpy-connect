import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/media/remote_display_settings.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app_icon.dart';

import 'product_flow_test.dart' show waitFor, tapPageAction;

/// 可选运行：tool/driver/remote_settings.dart 拥有隔离独立目标。产品动作使用真实控件与生产传输；直接请求仅用于夹具准备、观察与最终清理。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = int.fromEnvironment('CONNECT_E2E_PORT');
  final run = DateTime.now().microsecondsSinceEpoch.toString();
  Json? checkpoint;
  Json? hostResult;
  String? acknowledged, hostError;
  var sequence = 0;
  developer.registerExtension('ext.connect.remoteSettings', (
    _,
    parameters,
  ) async {
    if (checkpoint != null && parameters['ack'] == checkpoint!['id']) {
      acknowledged = parameters['ack'];
      hostError = parameters['error'];
      hostResult = parameters['result'] == null
          ? null
          : jsonDecode(parameters['result']!) as Json;
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'checkpoint': checkpoint}),
    );
  });
  binding.reportData = {'remoteSettingsComplete': false};
  testWidgets(
    'workspace settings control actual target geometry and screen lifecycle',
    (tester) async {
      expect(address, isNotEmpty);
      expect(port, inInclusiveRange(1, 65535));
      final semantics = tester.ensureSemantics();
      await app.main();
      await waitFor(
        tester,
        () => find.byType(ConnectApp).evaluate().isNotEmpty,
        reason: 'The production app must initialize.',
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      await waitFor(
        tester,
        () =>
            !controller.snapshot().loading &&
            !controller.snapshot().reconciliationPending,
        reason: 'Initial state must be verified.',
      );
      Future<Json> request(String command, [Json params = const {}]) =>
          controller
              .request(command, params)
              .timeout(const Duration(seconds: 40));
      final originalSettings = {...controller.snapshot().settings};
      final originalFocus = controller.snapshot().focusedDeviceId;
      String? deviceId, sessionId;
      final owned = <String>{};
      var createdDevice = false;
      Future<Json> host(String name, [Json details = const {}]) async {
        debugPrint('remote-settings-checkpoint: $name');
        acknowledged = null;
        hostError = null;
        hostResult = null;
        final id = '$run:${++sequence}:$name';
        checkpoint = {
          'id': id,
          'name': name,
          'deviceId': deviceId,
          'sessionId': sessionId,
          ...details,
        };
        // Android 停止为本 Activity 产帧时宿主确认仍须推进；tester.pump 会等待后续 resume-controller 检查点才可能到达的帧。
        final deadline = DateTime.now().add(const Duration(seconds: 50));
        while (acknowledged != id && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(acknowledged, id, reason: 'Independent host must verify $name.');
        if (hostError != null) throw StateError(hostError!);
        return hostResult ?? {};
      }

      final workspace = find.byType(DeviceWorkspacePage);
      Future<void> tapSetting(String label) =>
          tapPageAction(tester, workspace, find.text(label));
      Future<void> switchSetting(String label, bool next) async {
        await tester.scrollUntilVisible(
          find.text(label),
          250,
          scrollable: find
              .descendant(of: workspace, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 15,
        );
        final row = find.ancestor(
          of: find.text(label),
          matching: find.byType(ConnectSwitchRow),
        );
        await Scrollable.ensureVisible(tester.element(row), alignment: .5);
        await tester.pump(const Duration(milliseconds: 400));
        if (tester.widget<ConnectSwitchRow>(row).value != next) {
          expect(find.text(label).hitTestable(), findsOneWidget);
          await tester.tap(find.text(label).hitTestable());
          await tester.pump(const Duration(milliseconds: 300));
        }
        await waitFor(
          tester,
          () => tester.widget<ConnectSwitchRow>(row).value == next,
          reason: '$label must persist through the real settings transport.',
        );
      }

      Future<void> ratio(String label, {String? custom}) async {
        await tapSetting('画面设置');
        await waitFor(
          tester,
          () =>
              find.byType(QualityPage).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(QualityPage),
                    matching: find.byType(Scrollable),
                  )
                  .evaluate()
                  .isNotEmpty &&
              find.text('屏幕比例').evaluate().isNotEmpty,
          reason: 'The real device screen options must load before choosing a ratio.',
        );
        await tapPageAction(
          tester,
          find.byType(QualityPage),
          find.text('屏幕比例'),
        );
        await waitFor(
          tester,
          () =>
              find.text('自动适应可用空间').evaluate().isNotEmpty &&
              find.byType(Scrollable).evaluate().isNotEmpty,
          reason: 'The real ratio dialog must open.',
        );
        final option = find.widgetWithText(ListTile, label).last;
        await tester.scrollUntilVisible(
          option,
          150,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 8,
        );
        await tester.tap(option);
        await tester.pump(const Duration(milliseconds: 250));
        if (custom != null) {
          await tester.enterText(find.byType(TextField), custom);
          await tester.tap(find.text('保存').last);
        }
        await tester.pumpAndSettle();
        if (custom == null ||
            RemoteDisplaySettings.parseRatio(custom) != null) {
          final mode = switch (label) {
            '原始比例' => 'original',
            '自动适应可用空间' => 'auto',
            '自定义' => 'custom',
            _ => label,
          };
          await waitFor(
            tester,
            () {
              final saved = jsonObject(
                jsonObject(
                  controller.snapshot().settings['deviceSettings'],
                )[deviceId],
              );
              return saved['remoteAspectRatio'] == mode &&
                  (custom == null || saved['remoteCustomRatio'] == custom);
            },
            reason: 'The selected ratio must be persisted before creating a window.',
          );
          await tester.pageBack();
          await waitFor(
            tester,
            () =>
                workspace.evaluate().isNotEmpty &&
                find.byType(QualityPage).evaluate().isEmpty,
            reason: 'Return from screen settings before opening a new window.',
          );
        }
      }

      Future<Json> currentSession() async {
        final sessions = objects(
          (await request('session.list', {'deviceId': deviceId}))['sessions'],
        );
        return sessions.singleWhere(
          (session) => session['sessionId'] == sessionId,
        );
      }

      Future<void> openPhone({bool keyboard = false}) async {
        if (keyboard) {
          await waitFor(
            tester,
            () => ModalRoute.of(tester.element(workspace))?.isCurrent == true,
            reason: 'The workspace must own navigation before opening keyboard control.',
          );
          openRemoteRoute(
            tester.element(workspace),
            deviceId: deviceId!,
            requestKeyboard: true,
          );
        } else {
          await tapPageAction(
            tester,
            workspace,
            find.text('打开手机屏幕'),
            delta: -300,
          );
        }
        try {
          await waitFor(
            tester,
            () =>
                find.byType(Texture).evaluate().isNotEmpty &&
                find
                    .descendant(
                      of: find.byType(RemotePage),
                      matching: find.byType(CircularProgressIndicator),
                    )
                    .evaluate()
                    .isEmpty &&
                find.text('画面已暂停').evaluate().isEmpty,
            reason: 'Production Flutter must render a real target frame.',
          );
        } catch (_) {
          debugPrint(
            'remote-settings-open-failed keyboard=$keyboard insets=${tester.view.viewInsets} text=${find.byType(Text).evaluate().map((element) => (element.widget as Text).data).toList()} sessions=${await request('session.list', {'deviceId': deviceId})}',
          );
          rethrow;
        }
        final sessions = objects(
          (await request('session.list', {'deviceId': deviceId}))['sessions'],
        );
        final session = sessions.singleWhere(
          (entry) =>
              entry['packageName'] == null &&
              !['stopped', 'failed', 'error'].contains(entry['status']),
        );
        expect(session['firstFrameDecoded'], isTrue);
        expect(session['evidence'], 'media_codec.snapshot');
        sessionId = value(session, 'sessionId');
        owned.add(sessionId!);
        await waitFor(
          tester,
          () => find.byType(Texture).evaluate().isNotEmpty,
          reason: 'The real video surface must be live.',
        );
        final rect = tester.getRect(find.byType(Texture));
        expect(rect.width, greaterThan(0));
        expect(rect.height, greaterThan(0));
      }

      Future<void> geometry(
        String label, {
        double? ratio,
        bool auto = false,
        bool virtual = false,
      }) async {
        var session = await currentSession();
        final initialViewport = tester.getRect(
          find
              .ancestor(
                of: find.byType(Texture),
                matching: find.byType(Listener),
              )
              .first,
        );
        expect(
          initialViewport.top,
          0,
          reason:
              'The video drawable viewport includes the host top safe area.',
        );
        final expectedRatio = auto
            ? initialViewport.width / initialViewport.height
            : ratio;
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        bool coherentFrame() {
          final decodedWidth = session['decodedWidth'];
          final decodedHeight = session['decodedHeight'];
          if (decodedWidth is! num ||
              decodedHeight is! num ||
              decodedHeight <= 0) {
            return false;
          }
          final nativeRatio = decodedWidth / decodedHeight;
          final captureRatio =
              (session['width'] as num) / (session['height'] as num);
          final dynamic state = tester.state(find.byType(RemotePage));
          final Json presented = state.presentation.session as Json;
          final texture = tester.getRect(find.byType(Texture));
          return presented['width'] == session['width'] &&
              presented['height'] == session['height'] &&
              presented['decodedWidth'] == decodedWidth &&
              presented['decodedHeight'] == decodedHeight &&
              (nativeRatio - captureRatio).abs() < .005 &&
              (texture.width / texture.height - nativeRatio).abs() < .005 &&
              (expectedRatio == null ||
                  (nativeRatio - expectedRatio).abs() < .008);
        }

        while (!coherentFrame() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          session = await currentSession();
        }
        expect(
          coherentFrame(),
          isTrue,
          reason: 'Native output, presentation state and laid-out texture must converge.',
        );
        final actual =
            (session['decodedWidth'] as num) /
            (session['decodedHeight'] as num);
        final texture = tester.getRect(find.byType(Texture));
        expect(texture.width / texture.height, closeTo(actual, .005));
        final viewport = tester.getRect(
          find
              .ancestor(
                of: find.byType(Texture),
                matching: find.byType(Listener),
              )
              .first,
        );
        final expected = auto ? viewport.width / viewport.height : ratio;
        if (expected != null) expect(actual, closeTo(expected, .008));
        await host(label, {
          'ratio': expected,
          'decodedWidth': session['decodedWidth'],
          'decodedHeight': session['decodedHeight'],
          'captureWidth': session['width'],
          'captureHeight': session['height'],
          'textureId': session['textureId'],
          'captureGeneration': session['captureGeneration'],
          'generation': session['generation'],
          'viewportWidth': viewport.width,
          'viewportHeight': viewport.height,
          'virtual': virtual,
        });
      }

      Future<void> leave() async {
        final closingId = sessionId;
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pump();
        await tester.ensureVisible(find.text('关闭画面'));
        await tester.tap(find.text('关闭画面'));
        await waitFor(
          tester,
          () => find.byType(RemotePage).evaluate().isEmpty,
          reason: 'Explicit close removes the real control page.',
        );
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        List<Json> remaining;
        do {
          remaining =
              objects(
                    (await request('session.list', {
                      'deviceId': deviceId,
                    }))['sessions'],
                  )
                  .where(
                    (entry) =>
                        entry['sessionId'] == closingId &&
                        entry['status'] != 'stopped',
                  )
                  .toList();
          if (remaining.isEmpty) break;
          await tester.pump(const Duration(milliseconds: 100));
        } while (DateTime.now().isBefore(deadline));
        expect(
          remaining,
          isEmpty,
          reason: 'Closing must release this exact session instead of retaining it paused.',
        );
        owned.remove(closingId);
        await host('restored', {'closedSessionId': closingId});
      }

      Future<void> checkTopGesture() async {
        await host('top-shade-closed');
        final current = await currentSession();
        expect(current['sessionId'], sessionId);
        final frame = tester.getRect(find.byType(Texture));
        final start = Offset(frame.left + frame.width * .75, frame.top + 2);
        final end = Offset(start.dx, frame.top + frame.height * .45);
        final gesture = await tester.startGesture(start);
        for (var step = 1; step <= 10; step++) {
          await gesture.moveTo(Offset.lerp(start, end, step / 10)!);
          await tester.pump(const Duration(milliseconds: 80));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 600));
        try {
          await host('top-shade-open', {
            'sourceSessionId': sessionId,
            'textureTop': frame.top,
            'touchX': start.dx,
            'touchY': start.dy,
            'decodedWidth': current['width'],
            'decodedHeight': current['height'],
          });
        } finally {
          // 实际系统返回经过产品 PopScope 与远端键通道，必须收起目标通知栏，不能离开页面。
          await tester.binding.handlePopRoute();
          await tester.pump(const Duration(milliseconds: 600));
        }
        await host('top-shade-closed');
        expect(find.byType(RemotePage), findsOneWidget);
        expect((await currentSession())['sessionId'], sessionId);
        binding.reportData!['topSurfaceGestureAndRemoteBackVerified'] = true;
      }

      final originalHitTestPolicy =
          WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      Object? primaryFailure;
      try {
        expect(
          objects((await request('audio.sources'))['sources']),
          isEmpty,
          reason:
              'Use an isolated controller with no preexisting audio playback.',
        );
        final initial = objects((await request('devices.list'))['devices']);
        final added = await request('devices.add', {
          'address': address,
          'port': port,
          'transport': 'tcp',
          'attemptId': 'remote-settings-$run',
        });
        deviceId = value(added, 'deviceId');
        createdDevice = !initial.any((device) => device['id'] == deviceId);
        expect(
          createdDevice,
          true,
          reason: 'This test requires its own isolated target device record.',
        );
        await host('baseline');
        await controller.updateSetting('backgroundKeepAlive', true);
        await request('background.request', {
          'enabled': true,
          'askNotificationPermission': false,
        });
        binding.reportData!['backgroundKeepAliveTestEnabled'] = true;
        await request('observation.stop', {'deviceId': deviceId});
        await request('devices.connect', {'deviceId': deviceId});
        await controller.refreshDevices();
        WorkspaceRoute(deviceId: deviceId)
            .go(tester.element(find.byType(Scaffold).first));
        await waitFor(
          tester,
          () => workspace.evaluate().isNotEmpty,
          reason: 'Open the real device settings.',
        );
        await switchSetting('关闭最后画面时锁屏', false);
        await switchSetting('保持手机唤醒', false);
        await switchSetting('显示导航键', true);
        await ratio('原始比例');
        await openPhone();
        await geometry('original');
        await checkTopGesture();
        await leave();
        await ratio('自动适应可用空间');
        await openPhone();
        await geometry('auto-navigation', auto: true);
        await leave();
        await switchSetting('显示导航键', false);
        await openPhone();
        await tester.pump(const Duration(milliseconds: 800));
        await geometry('auto-no-navigation', auto: true);
        await leave();
        await openPhone(keyboard: true);
        await waitFor(
          tester,
          () => tester.view.viewInsets.bottom > 0,
          reason: 'An actual controller IME must be visible for this acceptance branch.',
        );
        final imeSession = await currentSession();
        debugPrint(
          'remote-settings-ime: insets=${tester.view.viewInsets.bottom} physical=${tester.view.physicalSize} display=${imeSession['displaySize']} decoded=${imeSession['width']}x${imeSession['height']}',
        );
        await host('ime-unchanged');
        await host('dismiss-ime');
        await waitFor(
          tester,
          () => tester.view.viewInsets.bottom == 0,
          reason: 'The actual IME must dismiss.',
        );
        await host('rotate-controller');
        await waitFor(
          tester,
          () =>
              tester.view.physicalSize.width > tester.view.physicalSize.height,
          reason: 'The actual Android controller must rotate to landscape.',
        );
        await tester.pump(const Duration(milliseconds: 800));
        await geometry('auto-landscape', auto: true);
        await host('restore-controller');
        await leave();
        for (final preset in [
          ('9:16', 9 / 16),
          ('3:4', 3 / 4),
          ('1:1', 1.0),
          ('16:9', 16 / 9),
        ]) {
          await ratio(preset.$1);
          await openPhone();
          await geometry(
            'preset-${preset.$1.replaceAll(':', '-')}',
            ratio: preset.$2,
          );
          await leave();
        }
        await ratio('自定义', custom: '2:3');
        await openPhone();
        await geometry('custom-2-3', ratio: 2 / 3);
        await leave();
        await ratio('自定义', custom: '0:1');
        expect(find.textContaining('请输入有效的宽:高'), findsOneWidget);
        expect(
          jsonObject(
            jsonObject(
              controller.snapshot().settings['deviceSettings'],
            )[deviceId],
          )['remoteCustomRatio'],
          '2:3',
        );
        if (find.text('取消').hitTestable().evaluate().isNotEmpty) {
          await tester.tap(find.text('取消').hitTestable().last);
          await tester.pumpAndSettle();
        }
        if (find.byType(QualityPage).evaluate().isNotEmpty) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await host('sleep-target');
        await switchSetting('新画面启动时点亮屏幕', true);
        await host('still-asleep');
        await tapSetting('断开设备连接');
        await waitFor(
          tester,
          () => find.text('断开连接').hitTestable().evaluate().isNotEmpty,
          reason: 'Wait for the real disconnect confirmation action.',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('断开连接').hitTestable().last);
        await waitFor(
          tester,
          () => controller.snapshot().devices.any(
            (device) =>
                device['id'] == deviceId &&
                device['status'] != 'connected' &&
                device['connectionId'] == null,
          ),
          reason: 'The production disconnect must finish.',
        );
        await tapPageAction(tester, workspace, find.text('连接手机'), delta: -300);
        await waitFor(
          tester,
          () => controller.snapshot().devices.any(
            (device) =>
                device['id'] == deviceId &&
                device['status'] == 'connected' &&
                device['connectionId'] != null,
          ),
          reason: 'The new device transport must connect without opening remote control.',
        );
        await host('connected-asleep');
        await switchSetting('保持手机唤醒', true);
        await openPhone();
        await host('new-screen-awake');
        await host('keep-active');
        await host('pause-controller');
        final pauseDeadline = DateTime.now().add(const Duration(seconds: 10));
        Json paused;
        do {
          paused = await currentSession();
          if (paused['status'] == 'paused') break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        } while (DateTime.now().isBefore(pauseDeadline));
        expect(
          paused['status'],
          'paused',
          reason: 'Actual host background pauses the still-open window.',
        );
        await host('keep-active-paused');
        await host('resume-controller');
        await waitFor(
          tester,
          () =>
              find.byType(Texture).evaluate().isNotEmpty &&
              find.text('画面已暂停').evaluate().isEmpty,
          reason: 'The same unclosed window must resume its rendered frame.',
        );
        expect((await currentSession())['sessionId'], sessionId);
        await leave();
        await host('keep-active-released');
        await switchSetting('关闭最后画面时锁屏', true);
        await openPhone();
        await leave();
        await host('exit-asleep');
        await host('wake-fixture');
        await tapPageAction(tester, workspace, find.text('全部应用'), delta: -300);
        await waitFor(
          tester,
          () => find.byType(AppsPage).evaluate().isNotEmpty,
          reason: 'Open the real installed application list.',
        );
        final applicationSearch = find.descendant(
          of: find.byType(AppsPage),
          matching: find.byType(TextField),
        );
        await waitFor(
          tester,
          () => applicationSearch.hitTestable().evaluate().isNotEmpty,
          reason: 'The real application inventory must finish loading its search field.',
        );
        await tester.enterText(applicationSearch, 'com.android.settings');
        final settingsApp = find.ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is PhoneAppIcon &&
                widget.packageName == 'com.android.settings',
          ),
          matching: find.byType(ListTile),
        );
        await waitFor(
          tester,
          () => settingsApp.evaluate().isNotEmpty,
          reason:
              'The isolated target must expose the launchable Settings app.',
        );
        await tester.tap(settingsApp);
        await waitFor(
          tester,
          () => find.text('在独立窗口打开').hitTestable().evaluate().isNotEmpty,
          reason: 'Wait for the real application action sheet.',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('在独立窗口打开').hitTestable());
        await waitFor(
          tester,
          () =>
              find.byType(Texture).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(RemotePage),
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty &&
              find.text('画面已暂停').evaluate().isEmpty,
          reason: 'Independent application must produce a real Flutter video texture.',
        );
        final application =
            objects(
              (await request('session.list', {
                'deviceId': deviceId,
              }))['sessions'],
            ).singleWhere(
              (session) => session['packageName'] == 'com.android.settings',
            );
        expect(application['firstFrameDecoded'], isTrue);
        expect(application['evidence'], 'media_codec.snapshot');
        sessionId = value(application, 'sessionId');
        owned.add(sessionId!);
        await geometry('application-custom', ratio: 2 / 3, virtual: true);
        final firstApplicationId = sessionId;
        await host('application-new-awake');
        await leave();
        await host('application-exit-asleep');
        final retainedTasks = await request('apps.list', {
          'deviceId': deviceId,
          'filter': 'running',
        });
        expect(
          objects(retainedTasks['apps'])
              .any((app) => app['packageName'] == 'com.android.settings'),
          isTrue,
          reason: 'Closing preserves and returns the actual application task.',
        );
        await tester.tap(settingsApp);
        await waitFor(
          tester,
          () => find.text('在独立窗口打开').hitTestable().evaluate().isNotEmpty,
          reason: 'Explicitly create a new application window from the application list.',
        );
        await tester.tap(find.text('在独立窗口打开').hitTestable());
        await waitFor(
          tester,
          () =>
              find.byType(Texture).evaluate().isNotEmpty &&
              find.text('画面已暂停').evaluate().isEmpty &&
              find
                  .descendant(
                    of: find.byType(RemotePage),
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty,
          reason: 'The new application window must render real pixels.',
        );
        final reopened =
            objects(
              (await request('session.list', {
                'deviceId': deviceId,
              }))['sessions'],
            ).singleWhere(
              (entry) => entry['packageName'] == 'com.android.settings',
            );
        sessionId = value(reopened, 'sessionId');
        owned.add(sessionId!);
        expect(
          sessionId,
          isNot(firstApplicationId),
          reason:
              'A closed window cannot be resumed under its former identity.',
        );
        await geometry('application-new-custom', ratio: 2 / 3, virtual: true);
        await host('application-new-awake');
        await leave();
        await host('application-exit-asleep');
        await tester.pageBack();
        await waitFor(
          tester,
          () => workspace.evaluate().isNotEmpty,
          reason: 'Return from applications to the workspace.',
        );
        binding.reportData!['remoteSettingsComplete'] = true;
      } catch (error, stack) {
        primaryFailure = error;
        binding.reportData!['failure'] = '$error';
        debugPrint('remote-settings-primary-failure: $error\n$stack');
        final Json displayState = {};
        if (find.byType(RemotePage).evaluate().isNotEmpty) {
          final dynamic state = tester.state(find.byType(RemotePage));
          displayState.addAll({
            'resizingDisplay': state.resizingDisplay,
            'displayViewport': '${state.displayViewport}',
            'requestedDisplaySize': '${state.requestedDisplaySize}',
            'appliedDisplaySize': '${state.appliedDisplaySize}',
            'waitingForIme': state.waitingForIme,
            'resizeTimerActive': state.resizeTimer?.isActive,
            'canSendInput': state.canSendInput,
            'hasInputAuthority': state.hasInputAuthority,
            'ownerCurrent': state.view?.isCurrent,
            'paused': state.presentation.paused,
            'controlAvailable': state.presentation.controlAvailable,
            'binding': '${state.presentation.binding}',
            'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
          });
          debugPrint('remote-settings-display-state: $displayState');
        }
        await host('failure', {
          'message': '$error',
          'displayState': displayState,
          'currentDevices': controller.snapshot().devices,
          'nativeDevices': (await request('devices.list'))['devices'],
          'settings': controller.snapshot().settings,
          'visibleTexts': find
              .byType(Text)
              .evaluate()
              .map((element) => (element.widget as Text).data)
              .whereType<String>()
              .toList(),
          'sessions': (await request('session.list', {
            'deviceId': deviceId,
          }))['sessions'],
          'controllerInset': tester.view.viewInsets.bottom,
          'controllerWidth': tester.view.physicalSize.width,
          'controllerHeight': tester.view.physicalSize.height,
        });
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        Future<void> clean(String label, Future<void> Function() action) async {
          try {
            await action();
          } catch (error) {
            cleanupErrors.add('$label: $error');
          }
        }

        Set<String>? remaining;
        await clean('live sessions', () async {
          remaining = objects(
            (await request('session.list', {'deviceId': deviceId}))['sessions'],
          ).map((entry) => value(entry, 'sessionId')).toSet();
        });
        for (final id in owned.where((id) => remaining?.contains(id) ?? true)) {
          await clean('session:$id', () async {
            await request('session.stop', {'sessionId': id});
          });
        }
        if (createdDevice && deviceId != null) {
          await clean('device:$deviceId', () async {
            await request('devices.forget', {'deviceId': deviceId});
          });
        }
        for (final key in ['deviceSettings', 'deviceQuality']) {
          if (originalSettings.containsKey(key)) {
            await clean(
              key,
              () => controller.updateSetting(key, originalSettings[key]),
            );
          }
        }
        await clean('backgroundKeepAlive', () async {
          final original = originalSettings['backgroundKeepAlive'] == true;
          await controller.updateSetting('backgroundKeepAlive', original);
          await request('background.request', {
            'enabled': original,
            'askNotificationPermission': false,
          });
          binding.reportData!['backgroundKeepAliveRestored'] = true;
        });
        await clean('focus', () => controller.focusDevice(originalFocus));
        await clean('target/controller', () async {
          await host('cleanup');
        });
        binding.reportData!['cleanupErrors'] = cleanupErrors;
        semantics.dispose();
        WidgetController.hitTestWarningShouldBeFatal = originalHitTestPolicy;
        if (primaryFailure == null) expect(cleanupErrors, isEmpty);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
