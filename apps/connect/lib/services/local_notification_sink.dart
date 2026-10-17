import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:scrcpy_connect/services/system_notifications.dart';

/// OS mechanics only. Object ownership, privacy and navigation stay in the
/// shared coordinator; notification callbacks never invoke a remote command.
class LocalNotificationSink implements SystemNotificationSink {
  LocalNotificationSink({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const notificationChannel = 'remote_notifications';
  static const callChannel = 'incoming_calls';
  final FlutterLocalNotificationsPlugin _plugin;
  final _activations = StreamController<String>.broadcast(sync: true);
  Future<void>? _initializing;

  @override
  Stream<String> get activations => _activations.stream;

  @override
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_connection'),
        iOS: darwin,
        macOS: darwin,
        linux: LinuxInitializationSettings(defaultActionName: '打开邻接'),
        windows: WindowsInitializationSettings(
          appName: '邻接',
          appUserModelId: 'dev.scrcpyconnect.Connect',
          guid: '9a9a2303-bc2d-4ec9-b408-ceb7b4d279fb',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.notificationResponseType ==
            NotificationResponseType.selectedNotification) {
          _activate(response.payload);
        }
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          notificationChannel,
          '远端实时通知',
          description: '被控设备仍有效的通知；正文仅在邻接中查看',
          importance: Importance.defaultImportance,
          playSound: false,
          enableVibration: false,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          callChannel,
          '远端来电提醒',
          description: '打开邻接查看来电，不自动接听或开启麦克风',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
        ),
      );
    }
    // A new process cannot attest to an old observation. Remove only our
    // namespace, preserving ConnectionService's 2101 and all other owners.
    if (!kIsWeb &&
        const [
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform)) {
      for (final active in await _plugin.getActiveNotifications()) {
        final id = active.id;
        if (id != null && _ownedId(id)) await _plugin.cancel(id: id);
      }
    }
    if (launch?.didNotificationLaunchApp == true) {
      _activate(launch?.notificationResponse?.payload);
    }
  }

  void _activate(String? payload) {
    if (payload != null && payload.isNotEmpty && payload.length <= 4096) {
      _activations.add(payload);
    }
  }

  bool _ownedId(int id) =>
      id >= systemNotificationIdMin && id <= systemNotificationIdMax;

  @override
  Future<SystemNotificationStatus> status() async {
    if (kIsWeb) {
      return const SystemNotificationStatus(reason: '此平台尚未验证系统提醒。');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android == null) return const SystemNotificationStatus();
        final allowed = await android.areNotificationsEnabled();
        final channels = await android.getNotificationChannels();
        bool? enabled(String id) {
          final channel = channels?.where((item) => item.id == id).firstOrNull;
          return channel == null ? null : channel.importance != Importance.none;
        }
        return SystemNotificationStatus(
          supported: true,
          permissionGranted: allowed,
          notificationChannelEnabled: enabled(notificationChannel),
          callChannelEnabled: enabled(callChannel),
          canRequest: allowed != true,
          canOpenSettings: true,
          reason: allowed == true
              ? '系统允许提醒；勿扰模式和各渠道设置仍可能影响展示。'
              : '系统通知尚未允许或已关闭；手机连接与实时观察不受此设置影响。',
        );
      case TargetPlatform.iOS:
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final permission = await ios?.checkPermissions();
        return _appleStatus(permission);
      case TargetPlatform.macOS:
        final mac = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        final permission = await mac?.checkPermissions();
        return _appleStatus(permission);
      case TargetPlatform.windows:
        return const SystemNotificationStatus(
          reason: 'Windows 系统提醒仍需验证打包身份及撤回行为。',
        );
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const SystemNotificationStatus(reason: '此平台尚未验证系统提醒。');
    }
  }

  SystemNotificationStatus _appleStatus(NotificationsEnabledOptions? value) =>
      SystemNotificationStatus(
        supported: true,
        permissionGranted: value?.isEnabled,
        canRequest: value?.isEnabled != true,
        canOpenSettings: true,
        reason: value?.isEnabled == true
            ? '系统允许提醒；展示方式由系统通知设置决定。'
            : '系统提醒尚未允许；可请求权限或前往系统设置。',
      );

  @override
  Future<SystemNotificationStatus> requestPermission() async {
    if (kIsWeb) return status();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      case TargetPlatform.iOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: false, badge: false);
      case TargetPlatform.macOS:
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: false, badge: false);
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        break;
    }
    return status();
  }

  @override
  Future<bool> openSettings() async {
    if (!(await status()).canOpenSettings) return false;
    return await _plugin.openAppNotificationSettings() ?? false;
  }

  @override
  Future<void> show(SystemNotice notice) async {
    if (!_ownedId(notice.id)) throw ArgumentError.value(notice.id, 'notice.id');
    final call = notice.kind == SystemNotificationKind.call;
    await _plugin.show(
      id: notice.id,
      title: notice.title,
      body: notice.body,
      payload: notice.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          call ? callChannel : notificationChannel,
          call ? '远端来电提醒' : '远端实时通知',
          icon: 'ic_connection',
          importance: call ? Importance.high : Importance.defaultImportance,
          priority: call ? Priority.high : Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          visibility: NotificationVisibility.private,
          autoCancel: true,
          category: call ? AndroidNotificationCategory.call : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
          threadIdentifier: 'interop-live',
        ),
        macOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
          threadIdentifier: 'interop-live',
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ownedId(id)) throw ArgumentError.value(id, 'id');
    await _plugin.cancel(id: id);
  }
}
