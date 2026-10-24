import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_direction_badge.dart';
import 'package:scrcpy_connect/presentation/transfer_presentation.dart';

class TransferResultRow extends StatelessWidget {
  const TransferResultRow({
    super.key,
    required this.transfer,
    required this.deviceName,
    this.onOpen,
  });

  final Json transfer;
  final String deviceName;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final issue = transferStatusHasIssue(value(transfer, 'status'));
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingXs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TransferDirectionBadge(transfer: transfer),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value(transfer, 'name', '文件'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: DesignTokens.spacingXxs),
                Text(
                  transferDetailDirection(transfer, deviceName),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: DesignTokens.spacingXxs),
                Text(
                  transferStatusDescription(transfer),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: issue ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ),
          if (onOpen != null)
            GlassMenuButton(
              icon: const Icon(LucideIcons.ellipsis),
              tooltip: '查看此项传输',
              actions: [
                GlassMenuAction(
                  label: '查看此项',
                  icon: const Icon(LucideIcons.info),
                  onPressed: onOpen,
                ),
              ],
            ),
        ],
      ),
    );
    return onOpen == null ? content : InkWell(onTap: onOpen, child: content);
  }
}
