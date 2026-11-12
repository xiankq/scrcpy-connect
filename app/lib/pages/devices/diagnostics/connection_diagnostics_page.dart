import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/pages/devices/diagnostics/widgets/device_function_checks.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class ConnectionDiagnosticsPage extends HookConsumerWidget {
  const ConnectionDiagnosticsPage({super.key, required this.device});
  final DeviceSnapshot device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revision = useState(0);
    final provider = deviceDiagnosisProvider(
      device.id,
      revision: revision.value,
    );
    final query = ref.watch(provider);
    return PageFrame(
      title: '连接诊断',
      child: ConnectionContent(
        child: AsyncContent(
          loading: query.isLoading,
          data: query.value,
          error: query.error,
          onRefresh: () => ref.invalidate(provider),
          emptyTitle: '暂时无法完成诊断',
          builder: (context, data) {
            final current = data.device;
            final connected = data.connected;
            final unauthorized =
                current.status == DeviceConnectionStatus.unauthorized;
            final usb = current.transport == DeviceTransport.usb;
            final reachable = data.tcpReachable;
            final identity = data.identityPresent;
            final checks = <({String name, bool ok, String message})>[
              (
                name: connected
                    ? '设备连接正常'
                    : unauthorized
                    ? '需要重新授权'
                    : '设备尚未连接',
                ok: connected,
                message: connected
                    ? '连接已建立。'
                    : unauthorized
                    ? '请在手机上重新授权，再检查连接。'
                    : '检查网络或 USB 状态，再连接手机。',
              ),
              if (usb)
                (
                  name: data.usbBackendAvailable == false
                      ? '当前平台无法使用 USB'
                      : connected
                      ? 'USB 连接已建立'
                      : 'USB 连接需要检查',
                  ok: connected,
                  message: data.usbBackendAvailable == false
                      ? '改用无线连接，并在手机上完成配对。'
                      : '检查主机角色与数据线；本机允许 USB 访问，手机允许调试。',
                )
              else
                (
                  name: reachable == true
                      ? '网络地址可达'
                      : reachable == false
                      ? '无法访问设备地址'
                      : '网络路径尚未检查',
                  ok: reachable == true,
                  message: reachable == true
                      ? '地址可达，仍需确认授权与连接。'
                      : reachable == false
                      ? '核对手机地址、连接端口和网络；跨网需已有 VPN 等可达路径。'
                      : '核对地址和连接端口后重新检查。',
                ),
              (
                name: identity == true
                    ? '本机授权身份已就绪'
                    : identity == false
                    ? '本机授权身份不可用'
                    : '本机授权身份尚未确认',
                ok: identity == true,
                message: identity == true
                    ? '以手机实际授权结果为准。'
                    : '检查本机授权身份，并在手机上确认授权。',
              ),
            ];
            final details = <Widget>[
              if (!usb && (current.address ?? '').isNotEmpty)
                StateNote(
                  '当前地址：${(current.address ?? '')} · 连接端口：${(current.port?.toString() ?? '未记录')}',
                ),
              SettingsGroup(
                children: [
                  for (final check in checks)
                    ListTile(
                      leading: ListIconBadge(
                        icon: check.ok == true
                            ? LucideIcons.circleCheck
                            : LucideIcons.circleAlert,
                        backgroundColor: check.ok == true
                            ? DesignTokens.colorListIconMint
                            : DesignTokens.colorListIconAmber,
                      ),
                      title: Text(
                        check.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      subtitle: check.ok == true
                          ? null
                          : Text(
                              check.message,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                    ),
                ],
              ),
              if ((current.reason ?? '').isNotEmpty)
                StateNote((current.reason ?? '')),
            ];
            final actions = <Widget>[
              const SizedBox(height: DesignTokens.spacingMd),
              FilledButton(
                onPressed: () => revision.value++,
                child: const Text('重新检查'),
              ),
              TextButton(
                onPressed: () =>
                    DeviceConnectionRoute(deviceId: device.id)
                        .push<void>(context),
                child: const Text('连接配置'),
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              const SectionTitle('功能检查'),
              DeviceFunctionChecks(device: current, refreshKey: revision.value),
            ];
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.all(DesignTokens.spacingMd) +
                  PageChromePadding.of(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...details, ...actions],
              ),
            );
          },
        ),
      ),
    );
  }
}
