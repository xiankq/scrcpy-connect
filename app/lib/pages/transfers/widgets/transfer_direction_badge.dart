import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';

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
