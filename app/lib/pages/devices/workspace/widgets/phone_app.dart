import 'dart:convert';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// Icons belong to a target device and package, never the host's icon set.
class PhoneAppIcon extends HookWidget {
  const PhoneAppIcon({
    super.key,
    required this.controller,
    required this.deviceId,
    required this.packageName,
    this.refreshKey,
    this.userId,
    this.size = DesignTokens.componentAppIconSize,
  });
  final AppController controller;
  final String deviceId;
  final String packageName;
  final Object? refreshKey;
  final String? userId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final future = useMemoized(() async {
      final result = await controller.request('apps.icon', {
        'deviceId': deviceId,
        'packageName': packageName,
      });
      if (result['deviceId'] != deviceId ||
          result['packageName'] != packageName ||
          result['mimeType'] != 'image/png' ||
          (userId != null && value(result, 'userId') != userId)) {
        return null;
      }
      final data = value(result, 'dataBase64');
      if (data.isEmpty || data.length > 2 * 1024 * 1024) return null;
      return base64Decode(data);
    }, [controller, deviceId, packageName, userId, refreshKey]);
    final result = useFuture<Uint8List?>(future, preserveState: false);
    Widget placeholder() => Icon(
      result.connectionState == ConnectionState.done
          ? LucideIcons.imageOff
          : LucideIcons.image,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: DesignTokens.componentIconSize,
      semanticLabel: result.connectionState == ConnectionState.done
          ? '图标暂不可用'
          : '正在读取图标',
    );
    return SizedBox.square(
      dimension: size,
      child: result.data == null
          ? Center(child: placeholder())
          : Image.memory(
              result.data!,
              fit: BoxFit.contain,
              gaplessPlayback: false,
              errorBuilder: (_, _, _) => Center(child: placeholder()),
            ),
    );
  }
}

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
