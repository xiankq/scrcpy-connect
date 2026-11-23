import 'dart:async';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/core/notifications/local_notification_sink.dart';
import 'package:scrcpy_connect/core/notifications/system_notification_sink_provider.dart';
import 'package:scrcpy_connect/widgets/app_session_scope.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

class AppStartup extends StatefulWidget {
  const AppStartup({
    super.key,
    required this.initialLocation,
    required this.loadSession,
    this.desktopWindow = false,
    this.initializeGlass = GlassMaterial.initialize,
  });

  final String initialLocation;
  final bool desktopWindow;
  final Future<AppBootstrap> Function() loadSession;
  final Future<void> Function() initializeGlass;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  final _appKey = GlobalKey();
  late final _notifications = LocalNotificationSink();
  AppBootstrap? _session;
  String? _failure;
  bool _loading = false;
  bool _glassReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prepareGlass());
      unawaited(_loadSession());
    });
  }

  Future<void> _prepareGlass() async {
    try {
      await widget.initializeGlass();
      if (mounted) setState(() => _glassReady = true);
    } catch (error) {
      debugPrint('Liquid glass initialization failed: $error');
    }
  }

  Future<void> _loadSession() async {
    if (_loading) return;
    _loading = true;
    if (_failure != null) setState(() => _failure = null);
    try {
      final session = await widget.loadSession();
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = failureMessage(error, fallback: '暂时无法读取应用数据。请重试。');
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return GlassMaterial.wrap(
      child: AppSessionScope(
        ready: session != null,
        failure: _failure,
        onRetry: _loadSession,
        child: ProviderScope(
          // Riverpod overrides are fixed per scope. Reparent the existing app
          // so the navigator and any selected tab survive session attachment.
          key: ObjectKey(session),
          overrides: session == null
              ? const []
              : [
                  ...session.overrides,
                  systemNotificationSinkProvider.overrideWithValue(
                    _notifications,
                  ),
                ],
          child: ConnectApp(
            key: _appKey,
            initialLocation: widget.initialLocation,
            glassReady: _glassReady,
            desktopWindow: widget.desktopWindow,
          ),
        ),
      ),
    );
  }
}
