import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';

class WorkspaceAppGrid extends StatelessWidget {
  const WorkspaceAppGrid({
    super.key,
    required this.title,
    required this.deviceId,
    required this.apps,
    required this.onOpen,
    required this.empty,
    this.action,
  });

  final String title;
  final String deviceId;
  final List<DeviceApp> apps;
  final ValueChanged<DeviceApp> onOpen;
  final Widget empty;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ContentPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            ?action,
          ],
        ),
        if (apps.isEmpty)
          Center(child: empty)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  (constraints.maxWidth / DesignTokens.componentAppCellWidth)
                      .floor()
                      .clamp(1, 6);
              return Wrap(
                children: [
                  for (final app in apps)
                    SizedBox(
                      width: constraints.maxWidth / columns,
                      child: Tooltip(
                        message: app.name,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            DesignTokens.roundedMd,
                          ),
                          onTap: () => onOpen(app),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: DesignTokens.componentRowHeight,
                            ),
                            child: Center(
                              child: PhoneAppIcon(
                                deviceId: deviceId,
                                packageName: app.packageName,
                                userId: app.userId,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );
}
