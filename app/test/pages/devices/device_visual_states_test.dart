import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_app.dart';
import 'package:scrcpy_connect/core/devices/models/device_call.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/device_setup/connection/widgets/connection_attempt_status.dart';
import 'package:scrcpy_connect/pages/devices/devices_page.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_card.dart';
import 'package:scrcpy_connect/pages/devices/widgets/first_device_illustration.dart';
import 'package:scrcpy_connect/pages/devices/workspace/device_workspace_page.dart';
import 'package:scrcpy_connect/pages/session_pending/session_content.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/app_session_scope.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';

const _phone = DeviceSnapshot(
  id: 'pixel',
  name: 'Pixel 8',
  androidVersion: '15',
  transport: .tls,
  status: .connected,
  battery: 78,
);
const _offline = DeviceSnapshot(
  id: 'redmi',
  name: 'Redmi Note 13',
  status: .offline,
  transport: .tls,
);
const _tablet = DeviceSnapshot(
  id: 'tablet',
  name: 'Galaxy Tab S9',
  model: 'SM-X710',
  status: .connected,
  transport: .usb,
);
const _failed = DeviceSnapshot(
  id: 'failed',
  name: 'Pixel 7a',
  status: .failed,
  transport: .tls,
);

void main() {
  testWidgets('应用启动时设备页的加载指示位于可用内容区中心', (tester) async {
    for (final (size, brightness, textScale) in [
      (const Size(390, 844), Brightness.light, 1.0),
      (const Size(320, 360), Brightness.dark, 2.0),
      (const Size(1200, 700), Brightness.dark, 1.0),
    ]) {
      await _show(
        tester,
        AppSessionScope(
          ready: false,
          failure: null,
          onRetry: () {},
          child: const AppSessionContent(
            title: '设备',
            root: true,
            child: DevicesPage(),
          ),
        ),
        size: size,
        brightness: brightness,
        textScale: textScale,
      );
      final loader = find.byType(ContentLoadingIndicator);
      final bounds = tester.getRect(
        find
            .ancestor(
              of: loader,
              matching: find.byWidgetPredicate(
                (widget) => widget is NotificationListener<ScrollNotification>,
              ),
            )
            .first,
      );
      final insets = PageChromePadding.of(tester.element(loader));
      expect(tester.getCenter(loader), insets.deflateRect(bounds).center);
      expect(find.text('设备'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('设备首次读取用列表骨架，已有设备刷新时行不移动', (tester) async {
    await _show(tester, const DevicesPage(), loading: true);
    await tester.pump(const Duration(milliseconds: 150));
    final skeleton = find.byType(SkeletonRows);
    expect(skeleton, findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(find.byKey(const ValueKey('page-search-open')), findsOneWidget);
    expect(find.byType(ContentLoadingIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _show(tester, const DevicesPage(), devices: [_offline]);
    final row = find.byType(DeviceCard);
    final beforeRefresh = tester.getRect(row);
    final container = ProviderScope.containerOf(tester.element(row));
    (container.read(deviceListProvider.notifier) as _Devices).startRefresh();
    await tester.pump();
    expect(tester.getRect(row), beforeRefresh);
    expect(find.byType(ContentLoadingIndicator), findsNothing);
  });

  testWidgets('设备列表按状态展示独立行尾动作，连接无需先打开菜单', (tester) async {
    final connections = _Connections();
    await _show(
      tester,
      const DevicesPage(),
      devices: [_phone, _offline, _tablet, _failed],
      connections: connections,
    );
    final first = find.byType(DeviceCard).first;
    final second = find.byType(DeviceCard).at(1);
    final add = find.byWidgetPredicate(
      (widget) => widget is GlassActionIcon && widget.tooltip == '添加设备',
    );
    final addSurface = find.ancestor(of: add, matching: find.byType(Glass));
    expect(tester.widget<Glass>(addSurface).circular, isTrue);
    expect(tester.getSize(addSurface), const Size.square(44));
    expect(tester.getCenter(addSurface), tester.getCenter(add));
    expect(tester.getTopRight(addSurface).dx, tester.getTopRight(first).dx);
    expect(tester.getSize(first).height, 108);
    expect(tester.getTopLeft(second).dy - tester.getBottomLeft(first).dy, 12);
    expect(find.text('打开屏幕'), findsNWidgets(2));
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(connections.starts, [_offline.id]);
    await tester.longPress(find.text('Redmi Note 13'));
    await tester.pumpAndSettle();
    expect(find.text('连接配置'), findsOneWidget);
    expect(find.text('移除此设备'), findsOneWidget);
  });

  testWidgets('页头搜索取得焦点，关闭后恢复标题、完整列表和同一滚动区', (tester) async {
    await _show(tester, const DevicesPage(), devices: [_phone, _offline]);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(find.text('设备'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);

    await tester.tap(find.byKey(const ValueKey('page-search-open')));
    await tester.pumpAndSettle();
    final editor = find.byType(EditableText);
    expect(find.text('设备'), findsNothing);
    expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);
    await tester.enterText(editor, 'Redmi');
    await tester.pumpAndSettle();
    expect(find.byType(DeviceCard), findsOneWidget);
    expect(find.text('Redmi Note 13'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('关闭搜索'));
    } finally {
      semantics.dispose();
    }
    await tester.pumpAndSettle();
    expect(find.text('设备'), findsOneWidget);
    expect(find.byType(DeviceCard), findsNWidgets(2));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable).first),
      same(scroll),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
  });

  testWidgets('首次添加在设备页显示完整靠近插画及通栏动作', (tester) async {
    await _show(tester, const DevicesPage());
    final art = find.byType(FirstDeviceIllustration);
    final action = find.widgetWithText(FilledButton, '添加设备');
    expect(tester.getSize(art), const Size(342, 270));
    expect(tester.getSize(action), const Size(342, 50));
    expect(tester.getTopLeft(action).dx, tester.getTopLeft(art).dx);
    expect(
      tester.getBottomLeft(art).dy,
      lessThan(tester.getTopLeft(find.text('添加第一台设备')).dy),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(AppBar, '设备'), findsOneWidget);
  });

  testWidgets('桌面页头在切换搜索时连续过渡并保留输入焦点', (tester) async {
    await _show(
      tester,
      const DesktopWindowInsets(
        left: 69,
        right: 0,
        top: 23,
        child: DevicesPage(),
      ),
      devices: [_phone],
      reducedMotion: false,
    );
    await tester.tap(find.byKey(const ValueKey('page-search-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final finder = find.byType(EditableText);
    expect(find.text('设备'), findsOneWidget);
    final editor = tester.state<EditableTextState>(finder);
    await tester.pumpAndSettle();
    expect(find.text('设备'), findsNothing);
    expect(tester.state<EditableTextState>(finder), same(editor));
    expect(tester.widget<EditableText>(finder).focusNode.hasFocus, isTrue);
  });

  testWidgets('首次添加靠近动效停在减少动态时的同一构图', (tester) async {
    await _show(tester, const DevicesPage(), reducedMotion: false);
    final card = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName.endsWith('intro-card.png'),
    );
    final initial = tester.getCenter(card);
    await tester.pump(const Duration(milliseconds: 320));
    final settled = tester.getCenter(card);
    expect(settled.dx, greaterThan(initial.dx));
    expect(settled.dy, lessThan(initial.dy));
    await _show(tester, const DevicesPage());
    expect(tester.getCenter(card), settled);
  });

  testWidgets('工作台读取当前连接的电量，并刷新实际充电状态', (tester) async {
    final phone = _phone.copyWith(
      connectionId: 'live',
      batteryUpdatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final inspection = _BatteryInspection();
    await _show(
      tester,
      DeviceWorkspacePage(device: phone, manageButton: null),
      devices: [phone],
      inspection: inspection,
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('78%'), findsNothing);
    expect(find.byIcon(LucideIcons.batteryCharging), findsNothing);
    expect(inspection.connections, ['live']);

    inspection.response = 'USB powered: true\nstatus: 2\nlevel: 63\nscale: 100';
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('63%'), findsOneWidget);
    expect(find.byIcon(LucideIcons.batteryCharging), findsOneWidget);

    inspection.response = 'USB powered: true\nstatus: 4\nlevel: 64\nscale: 100';
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('64%'), findsOneWidget);
    expect(find.byIcon(LucideIcons.batteryCharging), findsNothing);

    inspection.failed = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('64%'), findsNothing);
    expect(find.text('—'), findsOneWidget);

    inspection.failed = false;
    inspection.response = 'present: false\nstatus: 5\nlevel: 100\nscale: 100';
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsNothing);
    expect(find.text('—'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DeviceWorkspacePage)),
    );
    final devices = container.read(deviceListProvider.notifier) as _Devices;
    final readsBeforeDisconnect = inspection.connections.length;
    devices.setDevice(phone.copyWith(status: .offline, connectionId: null));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(inspection.connections, hasLength(readsBeforeDisconnect));
    expect(find.text('—'), findsOneWidget);

    inspection.response = 'status: 3\nlevel: 25\nscale: 50';
    devices.setDevice(phone.copyWith(connectionId: 'new'));
    await tester.pumpAndSettle();
    expect(inspection.connections.last, 'new');
    expect(find.text('50%'), findsOneWidget);
    expect(find.byIcon(LucideIcons.batteryCharging), findsNothing);
  });

  testWidgets('工作台空态左对齐，保持两张应用卡片的对应位置', (tester) async {
    await _show(
      tester,
      DeviceWorkspacePage(
        device: _phone.copyWith(
          batteryUpdatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
        onBack: () {},
        manageButton: GlassActionIcon(
          tooltip: '设备管理',
          onPressed: () {},
          icon: const Icon(Icons.settings_outlined),
        ),
      ),
    );
    final favoriteTitle = find.text('常用应用');
    final action = find.text('添加常用应用');
    final runningTitle = find.text('正在运行');
    final runningEmpty = find.text('当前没有正在运行的应用');
    expect(
      tester.getTopLeft(action).dx - tester.getTopLeft(favoriteTitle).dx,
      54,
    );
    expect(
      tester.getTopLeft(runningTitle).dx,
      tester.getTopLeft(favoriteTitle).dx,
    );
    expect(
      tester.getTopLeft(runningEmpty).dx - tester.getTopLeft(runningTitle).dx,
      31,
    );
    expect(
      tester.getTopLeft(runningTitle).dy - tester.getTopLeft(favoriteTitle).dy,
      124,
    );
    expect(find.text('全部应用').hitTestable(), findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('选择常用应用'), findsOneWidget);
    final done = find.widgetWithText(FilledButton, '完成');
    expect(done.hitTestable(), findsOneWidget);
    expect(find.ancestor(of: done, matching: find.byType(Glass)), findsNothing);
  });

  testWidgets('窄屏深色大字保留连接取消及工作台快捷入口', (tester) async {
    await _show(
      tester,
      DeviceWorkspacePage(
        device: _phone.copyWith(status: .connecting),
        onBack: () {},
        manageButton: null,
      ),
      size: const Size(300, 700),
      brightness: Brightness.dark,
      textScale: 2,
    );
    expect(find.text('取消连接').hitTestable(), findsOneWidget);
    final add = find.text('添加常用应用');
    await Scrollable.ensureVisible(tester.element(add), alignment: .5);
    await tester.pumpAndSettle();
    expect(add.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全屏连接等待保留设备、阶段和底部取消', (tester) async {
    var cancelled = false;
    await _show(
      tester,
      ConnectionAttemptStatus(
        busy: true,
        checking: false,
        cancelling: false,
        address: 'phone.local',
        paired: false,
        pairing: true,
        legacyTcp: false,
        onCancel: () => cancelled = true,
        onEdit: () {},
        onRetry: () {},
        onRecheck: () {},
      ),
    );
    final cancel = find.widgetWithText(OutlinedButton, '取消连接');
    expect(find.text('本机'), findsOneWidget);
    expect(find.text('手机'), findsOneWidget);
    expect(find.text('正在配对并查找手机的连接地址'), findsOneWidget);
    expect(tester.getRect(cancel), const Rect.fromLTWH(24, 746, 342, 50));
    await tester.tap(cancel);
    expect(cancelled, isTrue);
  });
}

Future<void> _show(
  WidgetTester tester,
  Widget page, {
  List<DeviceSnapshot> devices = const [],
  _Connections? connections,
  DeviceInspection? inspection,
  bool reducedMotion = true,
  bool loading = false,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceListProvider.overrideWith(() => _Devices(devices, loading)),
        deviceConnectionsProvider.overrideWithValue(
          connections ?? _Connections(),
        ),
        if (inspection != null)
          deviceInspectionProvider.overrideWithValue(inspection),
        runtimeEventsProvider.overrideWithValue(const Stream.empty()),
        recoveryStateProvider.overrideWith(_Recovery.new),
        preferencesProvider.overrideWith(_Preferences.new),
        audioErrorProvider.overrideWith(_Audio.new),
        deviceCallsSnapshotProvider(_phone.id).overrideWith(
          (_) async => const DeviceCallsSnapshot(deviceId: 'pixel'),
        ),
        runningDeviceAppsProvider(_phone.id).overrideWith(
          (_) async =>
              const RunningDeviceApps(deviceId: 'pixel', apps: [], userId: 0),
        ),
        installedDeviceAppsProvider(_phone.id)
            .overrideWith((_) async => const []),
      ],
      child: MaterialApp(
        theme: ConnectTokens.theme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 54, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 54, bottom: 34),
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  if (reducedMotion) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _Devices extends DeviceListNotifier {
  _Devices(this.devices, this.loading);

  final List<DeviceSnapshot> devices;
  final bool loading;

  @override
  DeviceListState build() =>
      DeviceListState(devices: devices, loading: loading);

  void startRefresh() => state = state.copyWith(loading: true);

  void setDevice(DeviceSnapshot device) =>
      state = state.copyWith(devices: [device]);

  @override
  Future<void> refresh() async {}
}

class _Connections implements DeviceConnectionControl {
  final starts = <String>[];

  @override
  Future<DeviceConnectionReceipt> connectDevice(
    String deviceId, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) async {
    starts.add(deviceId);
    return DeviceConnectionReceipt(
      device: _offline.copyWith(status: .connected),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}

class _Preferences extends PreferencesNotifier {
  @override
  PreferencesState build() => PreferencesState(values: Preferences());
}

class _Audio extends AudioErrorNotifier {
  @override
  String? build() => null;
}

class _BatteryInspection implements DeviceInspection {
  String response =
      'USB powered: true\nstatus: 5\npresent: true\nlevel: 100\nscale: 100';
  final connections = <String?>[];
  bool failed = false;

  @override
  Future<DeviceReading<DeviceBattery>> readBattery(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) async {
    connections.add(connectionId);
    if (failed) throw const RequestFailure('query_unavailable', '电池数据未读取。');
    return DeviceReading(
      deviceId: deviceId,
      connectionId: connectionId,
      value: DeviceBattery.fromDumpsys(response),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
