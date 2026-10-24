import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/router/navigation.dart';

/// 由用户选择手机屏幕或独立窗口，再导航到对应的应用启动入口。
Future<void> openPhoneApp(BuildContext context, Json device, Json app) async {
  final api = int.tryParse(value(device, 'apiLevel'));
  final mode = await showGlassModalSheet<String>(
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
                '打开“${value(app, 'name', value(app, 'packageName'))}”',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              if (api != null && api < 29) ...[
                const Text('此设备不支持独立窗口'),
                const SizedBox(height: DesignTokens.spacingSm),
              ],
              if (api == null || api >= 29)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'window'),
                  child: const Text('在独立窗口打开'),
                ),
              if (api == null || api >= 29)
                const SizedBox(height: DesignTokens.spacingSm),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'phone'),
                child: const Text('在手机屏幕打开'),
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
  if (mode != null && context.mounted) {
    await openRemoteRoute(
      context,
      deviceId: value(device, 'id'),
      packageName: value(app, 'packageName'),
      onPhoneScreen: mode == 'phone',
    );
  }
}
