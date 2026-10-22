import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/transfer_state.dart';

class TransferDirectionBadge extends StatelessWidget {
  const TransferDirectionBadge({super.key, required this.transfer});

  final Json transfer;

  @override
  Widget build(BuildContext context) {
    final issue = transferStatusHasIssue(value(transfer, 'status'));
    final push = transfer['direction'] == 'push';
    return ListIconBadge(
      icon: issue
          ? LucideIcons.circleAlert
          : push
          ? LucideIcons.arrowUpFromLine
          : LucideIcons.arrowDownToLine,
      backgroundColor: issue
          ? DesignTokens.colorListIconCoral
          : push
          ? DesignTokens.colorListIconBlue
          : DesignTokens.colorListIconAmber,
    );
  }
}
