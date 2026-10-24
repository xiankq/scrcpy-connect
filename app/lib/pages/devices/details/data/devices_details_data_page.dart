import 'package:scrcpy_connect/presentation/formatters.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_status.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceDataPage extends HookConsumerWidget {
  const DeviceDataPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revision = useState(0);
    final currentDevice =
        ref.watch(
          appControllerProvider.select(
            (state) => state.devices
                .where((entry) => entry['id'] == device['id'])
                .firstOrNull,
          ),
        ) ??
        {...device, 'status': 'offline', 'connectionId': null};
    final connectionId = currentDevice['status'] == 'connected'
        ? value(currentDevice, 'connectionId')
        : '';
    String shown(dynamic input, [String unit = '']) =>
        input == null || '$input'.isEmpty ? '未获取' : '$input$unit';
    String binary(dynamic input, String yes, String no) =>
        input is bool ? (input ? yes : no) : '未获取';
    String bytes(dynamic input) {
      if (input is! num || input < 0) return '未获取';
      return input >= 1024 * 1024 * 1024
          ? '${(input / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
          : '${(input / (1024 * 1024)).toStringAsFixed(0)} MB';
    }

    return PageFrame(
      title: '设备数据',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: () => revision.value++,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: CommandView(
        controller: controller,
        command: 'device.data.get',
        params: {
          'deviceId': device['id'],
          if (connectionId.isNotEmpty) 'connectionId': connectionId,
        },
        refreshKey: revision.value,
        emptyTitle: '设备数据暂不可用',
        builder: (context, data, refresh) {
          final system = jsonObject(data['system']);
          final battery = jsonObject(data['battery']);
          final display = jsonObject(data['display']);
          final network = jsonObject(data['network']);
          final memory = jsonObject(data['memory']);
          final storage = jsonObject(data['storage']);
          final failures = jsonObject(data['failures']);
          final stamp = num.tryParse('${data['observedAt']}');
          final updated = stamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(stamp.toInt() * 1000)
                    .toLocal();
          final groups = <(String, String, List<(String, IconData, String)>)>[
            (
              'system',
              '设备与系统',
              [
                ('设备型号', LucideIcons.smartphone, shown(system['model'])),
                (
                  '品牌 / 产品',
                  LucideIcons.tag,
                  '${shown(system['brand'])} / ${shown(system['product'])}',
                ),
                ('硬件', LucideIcons.cpu, shown(system['hardware'])),
                (
                  'Android / API',
                  LucideIcons.layers,
                  '${shown(system['androidVersion'])} / ${shown(system['apiLevel'])}',
                ),
                (
                  '安全补丁',
                  LucideIcons.shieldCheck,
                  shown(system['securityPatch']),
                ),
                ('处理器架构', LucideIcons.binary, shown(system['abi'])),
                ('构建版本', LucideIcons.package, shown(system['build'])),
                ('设备序列号', LucideIcons.fingerprint, shown(system['serial'])),
              ],
            ),
            (
              'battery',
              '电池与电源',
              [
                ('当前电量', LucideIcons.battery, shown(battery['level'], '%')),
                (
                  '充电状态',
                  LucideIcons.batteryCharging,
                  binary(battery['charging'], '正在充电', '未充电'),
                ),
                (
                  '电池健康',
                  LucideIcons.heart,
                  switch (battery['health']) {
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
                  shown(battery['temperatureC'], ' °C'),
                ),
                ('电压', LucideIcons.zap, shown(battery['voltageMv'], ' mV')),
                (
                  '实体屏幕',
                  LucideIcons.sun,
                  binary(display['screenOn'], '已点亮', '已熄屏'),
                ),
                (
                  '锁定状态',
                  LucideIcons.lock,
                  binary(display['locked'], '已锁定', '未锁定'),
                ),
              ],
            ),
            (
              'display',
              '屏幕与显示',
              [
                (
                  '分辨率',
                  LucideIcons.scan,
                  display['width'] == null || display['height'] == null
                      ? '未获取'
                      : '${display['width']} × ${display['height']} px',
                ),
                (
                  '逻辑密度',
                  LucideIcons.ruler,
                  shown(display['densityDpi'], ' dpi'),
                ),
                (
                  '刷新率',
                  LucideIcons.gauge,
                  shown(display['refreshRate'], ' Hz'),
                ),
              ],
            ),
            (
              'network',
              '网络与连接',
              [
                ('当前连接', LucideIcons.network, deviceTransportLabel(network)),
                (
                  '连接地址',
                  LucideIcons.wifi,
                  network['transport'] == 'usb'
                      ? 'USB'
                      : shown(network['address']),
                ),
                if (network['transport'] != 'usb')
                  ('连接端口', LucideIcons.network, shown(network['port'])),
                for (final entry in objects(network['addresses']))
                  (
                    value(entry, 'interface'),
                    LucideIcons.wifi,
                    shown(entry['address']),
                  ),
              ],
            ),
            (
              'memory',
              '内存与存储',
              [
                (
                  '运行内存',
                  LucideIcons.cpu,
                  '${bytes(memory['totalBytes'])} · 可用 ${bytes(memory['availableBytes'])}',
                ),
                (
                  '内部存储',
                  LucideIcons.hardDrive,
                  '${bytes(storage['totalBytes'])} · 可用 ${bytes(storage['availableBytes'])}',
                ),
                (
                  '处理器核心',
                  LucideIcons.cpu,
                  shown(jsonObject(data['processor'])['cores'], ' 核'),
                ),
              ],
            ),
          ];
          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              StateNote(deviceName(device), icon: LucideIcons.smartphone),
              if (data['stale'] == true)
                const StateNote('设备离线，以下为本机记录；动态数据尚未更新。'),
              if (updated != null)
                StateNote(
                  '${data['stale'] == true ? '最近连接' : '更新于'} ${updated.toString().split('.').first}',
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
                      StateNote(
                        value(
                          jsonObject(failures[group.$1]),
                          'message',
                          '部分数据未获取',
                        ),
                      ),
                    if (group.$1 == 'memory' && failures['storage'] != null)
                      const StateNote('存储信息未获取'),
                    if (group.$1 == 'battery' && failures['power'] != null)
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
