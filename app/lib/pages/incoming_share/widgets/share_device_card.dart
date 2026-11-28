import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 接收设备卡（Ardot T3 2:1716 设备卡）：设备块、名称与连接方式，行尾为单选标记。
class ShareDeviceCard extends StatelessWidget {
  const ShareDeviceCard({
    super.key,
    required this.device,
    required this.selected,
    required this.onTap,
  });
  final DeviceSnapshot device;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    child: ContentPanel(
      padding: EdgeInsets.zero,
      child: AppListRow(
        selected: selected,
        onTap: onTap,
        leading: DeviceIdentity(device: device),
        title: Text(deviceName(device)),
        subtitle: Text('已连接 · ${deviceTransportLabel(device)}'),
        subtitleMaxLines: 1,
        trailing: SelectionMark(selected: selected),
      ),
    ),
  );
}
