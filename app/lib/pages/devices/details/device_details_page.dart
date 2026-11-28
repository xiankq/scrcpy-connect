import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// 读取中行尾值占位宽度（约为常见值的宽度）。
const _valuePlaceholderWidth = 96.0;

/// 读取值最多占行宽的比例；值完整换行显示，不截断。
const _valueMaxWidthFactor = .5;

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
    final zeroFraction = RegExp(r'\.0$');
    String shown(Object? input, [String unit = '']) {
      final text = input?.toString();
      if (text == null || text.isEmpty) return '未获取';
      final value = input is double
          ? text.replaceFirst(zeroFraction, '')
          : text;
      return '$value$unit';
    }

    String binary(bool? input, String yes, String no) => input == null
        ? '未获取'
        : input
        ? yes
        : no;
    String bytes(int? input) {
      if (input == null || input < 0) return '未获取';
      const megabyte = 1024 * 1024;
      const gigabyte = 1024 * megabyte;
      if (input < gigabyte) {
        return '${(input / megabyte).toStringAsFixed(0)} MB';
      }
      final value = (input / gigabyte).toStringAsFixed(1);
      return '${value.replaceFirst(zeroFraction, '')} GB';
    }

    Widget buildDetails(
      BuildContext context,
      DeviceReading<DeviceDetails>? reading,
    ) {
      final loading = reading == null;
      final data = reading?.value ?? const DeviceDetails();
      final system = data.system;
      final battery = data.battery;
      final display = data.display;
      final network = data.network;
      final transport = loading ? currentDevice.transport : network.transport;
      final memory = data.memory;
      final storage = data.storage;
      final failures = data.failures;
      final stamp = reading?.observedAt;
      final updated = stamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(stamp * 1000).toLocal();
      final groups = <(DeviceDetailSection, String, List<(String, String)>)>[
        (
          DeviceDetailSection.system,
          '设备与系统',
          [
            ('设备型号', shown(system.model)),
            ('品牌 / 产品', '${shown(system.brand)} / ${shown(system.product)}'),
            ('硬件', shown(system.hardware)),
            (
              'Android / API',
              '${shown(system.androidVersion)} / ${shown(system.apiLevel)}',
            ),
            ('安全补丁', shown(system.securityPatch)),
            ('处理器架构', shown(system.abi)),
            ('构建版本', shown(system.build)),
            ('设备序列号', shown(system.serial)),
          ],
        ),
        (
          DeviceDetailSection.battery,
          '电池与电源',
          [
            ('当前电量', shown(battery.level, '%')),
            ('充电状态', deviceBatteryStatusLabel(battery.status) ?? '未获取'),
            (
              '电池健康',
              switch (battery.health) {
                2 => '良好',
                3 => '过热',
                4 => '电池失效',
                5 => '过压',
                6 => '电池异常',
                7 => '温度过低',
                _ => '未获取',
              },
            ),
            ('温度', shown(battery.temperatureC, ' °C')),
            ('电压', shown(battery.voltageMv, ' mV')),
            ('实体屏幕', binary(display.screen.screenOn, '已点亮', '已熄屏')),
            ('锁定状态', binary(display.screen.locked, '已锁定', '未锁定')),
          ],
        ),
        (
          DeviceDetailSection.display,
          '屏幕与显示',
          [
            (
              '分辨率',
              display.width == null || display.height == null
                  ? '未获取'
                  : '${display.width} × ${display.height} px',
            ),
            ('逻辑密度', shown(display.densityDpi, ' dpi')),
            ('刷新率', shown(display.refreshRate, ' Hz')),
          ],
        ),
        (
          DeviceDetailSection.network,
          '网络与连接',
          [
            ('当前连接', deviceTransportLabel(currentDevice)),
            (
              '连接地址',
              transport == DeviceTransport.usb ? 'USB' : shown(network.address),
            ),
            if (transport != DeviceTransport.usb) ('连接端口', shown(network.port)),
            for (final entry in network.addresses)
              (entry.interface, shown(entry.address)),
          ],
        ),
        (
          DeviceDetailSection.memory,
          '内存与存储',
          [
            (
              '运行内存',
              '${bytes(memory.totalBytes)} · 可用 ${bytes(memory.availableBytes)}',
            ),
            (
              '共享存储',
              '${bytes(storage.totalBytes)} · 可用 ${bytes(storage.availableBytes)}',
            ),
            ('处理器核心', shown(data.cpuCores, ' 核')),
          ],
        ),
      ];
      final timestamp = updated?.toString().split('.').first;
      // 设备详情（Ardot H13 2:615）：每组一个组头加分组卡片，行尾为读取值。
      final sections = <Widget>[
        for (final (index, (section, title, fields)) in groups.indexed) ...[
          SectionTitle(title, first: index == 0),
          SettingsGroup(
            children: [
              for (final (label, value) in fields)
                _DetailRow(label: label, value: loading ? null : value),
            ],
          ),
          if (failures[section] case final failure?)
            StateNote(
              failureCodeMessage(
                failure.code,
                fallback: '无法读取这部分信息。请检查手机连接后刷新。',
              ),
            ),
          if (section == DeviceDetailSection.memory &&
              failures[DeviceDetailSection.storage] != null)
            const StateNote('存储信息未获取'),
          if (section == DeviceDetailSection.battery &&
              failures[DeviceDetailSection.power] != null)
            const StateNote('屏幕与锁定状态未获取'),
        ],
      ];
      return GroupedListView(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentPagePadding,
        ),
        children: [
          if (loading)
            LoadingSkeleton(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sections,
              ),
            )
          else ...[
            if (reading.stale)
              StateNote(
                timestamp == null
                    ? '手机已断开。以下是上次读取的信息。'
                    : '手机已断开。以下是上次读取的信息。\n最近连接 $timestamp',
              ),
            ...sections,
            if (!reading.stale && timestamp != null)
              StateNote('更新于 $timestamp'),
          ],
        ],
      );
    }

    return PageFrame(
      title: '设备详情',
      actions: [
        GlassActionIcon(
          tooltip: '刷新',
          onPressed: refresh,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      child: AsyncContent<DeviceReading<DeviceDetails>>(
        loading: query.isLoading,
        data: query.value,
        error: query.isLoading ? null : query.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取设备信息',
        loadingPlaceholder: Builder(
          builder: (context) => buildDetails(context, null),
        ),
        builder: buildDetails,
      ),
    );
  }
}

/// 读取值行：标题为字段名，行尾为 `subheadline` + `text-secondary` 的读取值，
/// 长值在行尾完整换行（共用行尾值最多两行，这里需要完整可读）；[value] 为空时显示占位。
class _DetailRow extends StatelessWidget implements GroupedRow {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  double get separatorIndent => listRowSeparatorIndent(null);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AppListRow(
      // 值放在标题行内而不是行尾槽：行尾槽限高，长值需要完整换行。
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: DesignTokens.componentListRowGap),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * _valueMaxWidthFactor,
            ),
            child: switch (value) {
              final value? => Text(
                value,
                textAlign: TextAlign.end,
                style: AppTypography.of(context).subheadline
                    .copyWith(color: AppColors.of(context).textSecondary),
              ),
              null => const SizedBox(
                width: _valuePlaceholderWidth,
                child: SkeletonLine(
                  fraction: .64,
                  alignment: AlignmentDirectional.centerEnd,
                ),
              ),
            },
          ),
        ],
      ),
    ),
  );
}
