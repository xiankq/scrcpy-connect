import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/display_labels.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/command_query.dart';

class WorkspaceCallCard extends HookWidget {
  const WorkspaceCallCard({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final id = value(device, 'id');
    final online = device['status'] == 'connected';
    final query = useMemoized(
      () => online
          ? CommandQuery(
              request: controller.request,
              events: controller.eventStream(),
              command: 'calls.list',
              params: {'deviceId': id},
            )
          : null,
      [controller, id, online],
    );
    useListenable(query);
    useEffect(() => query?.dispose, [query]);
    final data = query?.data;
    final call =
        data?['live'] == true &&
            query?.error == null &&
            ['available', 'limited'].contains(data?['status'])
        ? objects(data?['calls'])
              .where(
                (call) => [
                  'ringing',
                  'active',
                  'dialing',
                  'connecting',
                ].contains(call['state']),
              )
              .firstOrNull
        : null;
    if (call == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spacingMd),
      child: ContentPanel(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const ListIconBadge(
            icon: LucideIcons.phone,
            backgroundColor: DesignTokens.colorListIconMint,
          ),
          title: Text(
            call['aggregate'] == true
                ? '来电者未知'
                : value(call, 'name', value(call, 'number', '来电者未知')),
          ),
          subtitle: Text(
            '${deviceName(device)} · ${statusText(value(call, 'state'))}\n声音仍在手机',
          ),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => CallsRoute(deviceId: id).push<void>(context),
        ),
      ),
    );
  }
}
