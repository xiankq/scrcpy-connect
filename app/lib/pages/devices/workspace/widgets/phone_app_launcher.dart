import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

Future<void> openPhoneApp(
  BuildContext context,
  AppController controller,
  Json device,
  Json app, {
  bool changeMode = false,
  bool existingTask = false,
}) async {
  final deviceId = value(device, 'id');
  final package = value(app, 'packageName');
  final release = controller.claimAppOpen(deviceId, package);
  if (release == null) return;
  try {
    Future<List<Json>> sessions() async {
      final result = await controller.request('session.list', {
        'deviceId': deviceId,
      });
      if (result['sessions'] is! List) {
        throw const RequestFailure(
          'session_state_unknown',
          '暂时无法核对已有画面，请稍后重试。',
        );
      }
      return objects(result['sessions'])
          .where((session) => session['deviceId'] == deviceId)
          .toList();
    }

    Json? pending(List<Json> list) => list
        .where(
          (session) =>
              session['packageName'] == package &&
              session['launchOutcome'] == 'unknown',
        )
        .firstOrNull;
    Json? retained(List<Json> list) => list
        .where(
          (session) =>
              session['packageName'] == package &&
              session['recordOnly'] != true &&
              !['stopped', 'failed', 'error'].contains(session['status']),
        )
        .firstOrNull;
    Future<void> openRecord(Json record) => openRemoteRoute(
      context,
      deviceId: deviceId,
      sessionId: value(record, 'sessionId', value(record, 'id')),
    );

    var list = await sessions();
    if (!context.mounted) return;
    final unknown = pending(list);
    if (unknown != null) {
      await openRecord(unknown);
      return;
    }
    final active = retained(list);
    if (active != null && !changeMode) {
      await openRecord(active);
      return;
    }
    final api = int.tryParse(
      value(controller.currentDevice(device), 'apiLevel'),
    );
    var mode = controller.appOpenMode(deviceId, package);
    final choose =
        changeMode ||
        mode == null ||
        mode == 'window' && (api == null || api < 29);
    if (choose) {
      mode = await _chooseMode(
        context,
        app,
        windowAvailable: api == null || api >= 29,
      );
      if (mode == null || !context.mounted) return;
      list = await sessions();
      if (!context.mounted) return;
      final unknown = pending(list);
      if (unknown != null) {
        await openRecord(unknown);
        return;
      }
    }
    final current = retained(list);
    if ((current != null && mode == 'phone' ||
            mode == 'window' && existingTask && current == null) &&
        !await confirm(
          context,
          '切换应用打开方式？',
          '这可能移动手机上已有的应用任务，原画面可能随之改变。',
          action: '继续打开',
        )) {
      return;
    }
    if (!context.mounted) return;
    if (choose) {
      await controller.rememberAppOpenMode(deviceId, package, mode);
      if (!context.mounted) return;
    }
    if (current != null && mode == 'window') {
      await openRecord(current);
      return;
    }
    await openRemoteRoute(
      context,
      deviceId: deviceId,
      packageName: package,
      onPhoneScreen: mode == 'phone',
    );
  } catch (error) {
    if (context.mounted) feedback(context, '$error');
  } finally {
    release();
  }
}

Future<String?> _chooseMode(
  BuildContext context,
  Json app, {
  required bool windowAvailable,
}) => showGlassModalSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              value(app, 'name', value(app, 'packageName')),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'phone'),
              child: const Text('在手机屏幕打开'),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Tooltip(
              message: windowAvailable ? '' : '此设备当前不支持独立窗口',
              child: OutlinedButton(
                onPressed: windowAvailable
                    ? () => Navigator.pop(context, 'window')
                    : null,
                child: const Text('在独立窗口打开'),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ),
  ),
);
