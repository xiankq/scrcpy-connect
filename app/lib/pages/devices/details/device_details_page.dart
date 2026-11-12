import 'package:flutter/material.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceDetailsPage extends ConsumerWidget {
  const DeviceDetailsPage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDevice =
        ref.watch(
          deviceListProvider.select(
            (state) => state.devices
                .where((entry) => entry.id == device.id)
                .firstOrNull,
          ),
        ) ??
        device.copyWith(
          status: DeviceConnectionStatus.offline,
          connectionId: null,
        );
    final connectionId =
        currentDevice.status == DeviceConnectionStatus.connected
        ? (currentDevice.connectionId ?? '')
        : '';
    final provider = deviceDetailsProvider(
      device.id,
      connectionId: connectionId.isEmpty ? null : connectionId,
    );
    final query = ref.watch(provider);
    void refresh() => ref.invalidate(provider);
    String shown(Object? input, [String unit = '']) =>
        input == null || '$input'.isEmpty ? '未获取' : '$input$unit';
    String binary(bool? input, String yes, String no) => input == null
        ? '未获取'
        : input
        ? yes
        : no;
    String bytes(int? input) {
      if (input == null || input < 0) return '未获取';
      return input >= 1024 * 1024 * 1024
          ? '${(input / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
          : '${(input / (1024 * 1024)).toStringAsFixed(0)} MB';
    }

    return PageFrame(
      title: '设备详情',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: refresh,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: AsyncContent<DeviceReading<DeviceDetails>>(
        loading: query.isLoading,
        data: query.value,
        error: query.isLoading ? null : query.error,
        onRefresh: refresh,
        emptyTitle: '设备数据暂不可用',
        builder: (context, reading) {
          final data = reading.value;
          final system = data.system;
          final battery = data.battery;
          final display = data.display;
          final network = data.network;
          final memory = data.memory;
          final storage = data.storage;
          final failures = data.failures;
          final stamp = reading.observedAt;
          final updated = stamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(stamp * 1000).toLocal();
          final groups = <(DeviceDetailSection, String, List<(String, IconData, String)>)>[
            (
              DeviceDetailSection.system,
              '设备与系统',
              [
                ('设备型号', LucideIcons.smartphone, shown(system.model)),
                (
                  '品牌 / 产品',
                  LucideIcons.tag,
                  '${shown(system.brand)} / ${shown(system.product)}',
                ),
                ('硬件', LucideIcons.cpu, shown(system.hardware)),
                (
                  'Android / API',
                  LucideIcons.layers,
                  '${shown(system.androidVersion)} / ${shown(system.apiLevel)}',
                ),
                ('安全补丁', LucideIcons.shieldCheck, shown(system.securityPatch)),
                ('处理器架构', LucideIcons.binary, shown(system.abi)),
                ('构建版本', LucideIcons.package, shown(system.build)),
                ('设备序列号', LucideIcons.fingerprint, shown(system.serial)),
              ],
            ),
            (
              DeviceDetailSection.battery,
              '电池与电源',
              [
                ('当前电量', LucideIcons.battery, shown(battery.level, '%')),
                (
                  '充电状态',
                  LucideIcons.batteryCharging,
                  binary(battery.charging, '正在充电', '未充电'),
                ),
                (
                  '电池健康',
                  LucideIcons.heart,
                  switch (battery.health) {
                    2 => '良好',
                    3 => '过热',
                    4 => '电池失效',
                    5 => '过压',
                    7 => '温度过低',
                    _ => '未获取',
                  },
                ),
                (
                  '温度',
                  LucideIcons.thermometer,
                  shown(battery.temperatureC, ' °C'),
                ),
                ('电压', LucideIcons.zap, shown(battery.voltageMv, ' mV')),
                (
                  '实体屏幕',
                  LucideIcons.sun,
                  binary(display.screen.screenOn, '已点亮', '已熄屏'),
                ),
                (
                  '锁定状态',
                  LucideIcons.lock,
                  binary(display.screen.locked, '已锁定', '未锁定'),
                ),
              ],
            ),
            (
              DeviceDetailSection.display,
              '屏幕与显示',
              [
                (
                  '分辨率',
                  LucideIcons.scan,
                  display.width == null || display.height == null
                      ? '未获取'
                      : '${display.width} × ${display.height} px',
                ),
                ('逻辑密度', LucideIcons.ruler, shown(display.densityDpi, ' dpi')),
                ('刷新率', LucideIcons.gauge, shown(display.refreshRate, ' Hz')),
              ],
            ),
            (
              DeviceDetailSection.network,
              '网络与连接',
              [
                (
                  '当前连接',
                  LucideIcons.network,
                  deviceTransportLabel(currentDevice),
                ),
                (
                  '连接地址',
                  LucideIcons.wifi,
                  network.transport == DeviceTransport.usb
                      ? 'USB'
                      : shown(network.address),
                ),
                if (network.transport != DeviceTransport.usb)
                  ('连接端口', LucideIcons.network, shown(network.port)),
                for (final entry in network.addresses)
                  (entry.interface, LucideIcons.wifi, shown(entry.address)),
              ],
            ),
            (
              DeviceDetailSection.memory,
              '内存与存储',
              [
                (
                  '运行内存',
                  LucideIcons.cpu,
                  '${bytes(memory.totalBytes)} · 可用 ${bytes(memory.availableBytes)}',
                ),
                (
                  '共享存储',
                  LucideIcons.hardDrive,
                  '${bytes(storage.totalBytes)} · 可用 ${bytes(storage.availableBytes)}',
                ),
                ('处理器核心', LucideIcons.cpu, shown(data.cpuCores, ' 核')),
              ],
            ),
          ];
          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              StateNote(deviceName(device), icon: LucideIcons.smartphone),
              if (reading.stale) const StateNote('设备离线，以下为本机记录；动态数据尚未更新。'),
              if (updated != null)
                StateNote(
                  '${reading.stale ? '最近连接' : '更新于'} ${updated.toString().split('.').first}',
                ),
              for (final group in groups) ...[
                SectionTitle(group.$2),
                SettingsGroup(
                  children: [
                    for (final field in group.$3)
                      ListTile(
                        leading: ListIconBadge(
                          icon: field.$2,
                          backgroundColor: functionalIconColor(field.$2),
                        ),
                        title: Text(
                          field.$1,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        subtitle: Text(
                          field.$3,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                          vertical: DesignTokens.spacingXs,
                        ),
                      ),
                    if (failures[group.$1] != null)
                      StateNote(failures[group.$1]!.message),
                    if (group.$1 == DeviceDetailSection.memory &&
                        failures[DeviceDetailSection.storage] != null)
                      const StateNote('存储信息未获取'),
                    if (group.$1 == DeviceDetailSection.battery &&
                        failures[DeviceDetailSection.power] != null)
                      const StateNote('屏幕与锁定状态未获取'),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
