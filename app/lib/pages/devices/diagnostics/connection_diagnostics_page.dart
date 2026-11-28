import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/pages/devices/diagnostics/widgets/device_function_checks.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
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
    // 连接诊断（Ardot H16 2:704）：连接检查、处理入口与功能检查分组，底部通栏「重新检查」。
    return PageFrame(
      title: '连接诊断',
      bottom: query.hasValue
          ? AppButton(
              role: AppButtonRole.primary,
              expand: true,
              onPressed: () => revision.value++,
              label: '重新检查',
            )
          : null,
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
                      : '请换一根可传输数据的 USB 线，解锁手机并允许 USB 调试。',
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
                      ? '请确认两台设备连着同一 Wi-Fi，再核对手机上的地址和端口。'
                      : '核对地址和连接端口后重新检查。',
                ),
              (
                name: identity == true
                    ? '本机授权身份已就绪'
                    : identity == false
                    ? '暂时无法读取本机的调试授权'
                    : '暂时无法确认本机的调试授权',
                ok: identity == true,
                message: identity == true
                    ? '以手机实际授权结果为准。'
                    : '请检查本机的调试设置，并在手机上允许调试。',
              ),
            ];
            final colors = AppColors.of(context);
            final details = <Widget>[
              if (!usb && (current.address ?? '').isNotEmpty)
                StateNote(
                  '当前地址：${(current.address ?? '')} · 连接端口：${(current.port?.toString() ?? '未记录')}',
                ),
              const SectionTitle('连接检查', first: true),
              SettingsGroup(
                children: [
                  for (final check in checks)
                    AppListRow(
                      title: Text(check.name),
                      subtitle: check.ok ? null : Text(check.message),
                      trailing: Icon(
                        check.ok
                            ? LucideIcons.circleCheck
                            : LucideIcons.circleAlert,
                        size: DesignTokens.componentSectionGlyphSize,
                        color: check.ok ? colors.success : colors.warning,
                      ),
                    ),
                ],
              ),
              if ((current.reason ?? '').isNotEmpty)
                const StateNote('设备连接出现问题。请检查手机是否开着，再按下方提示重新连接。'),
            ];
            final actions = <Widget>[
              const SizedBox(height: DesignTokens.componentListSectionGap),
              SettingsGroup(
                children: [
                  ActionRow(
                    icon: AppIcons.viewOptions,
                    color: FunctionTone.connection,
                    title: '连接配置',
                    onTap: () =>
                        DeviceConnectionRoute(deviceId: device.id)
                            .push<void>(context),
                  ),
                ],
              ),
              const SectionTitle('功能检查'),
              DeviceFunctionChecks(device: current, refreshKey: revision.value),
            ];
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(
                    horizontal: DesignTokens.componentPagePadding,
                  ) +
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
