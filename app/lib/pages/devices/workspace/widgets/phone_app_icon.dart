import 'package:scrcpy_connect/application/transport/json_readers.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/application/app_controller.dart';

/// 图标属于目标设备与包名，不使用主控设备的图标集合。
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
