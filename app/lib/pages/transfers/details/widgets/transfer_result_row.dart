import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_direction_badge.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';

class TransferResultRow extends StatelessWidget {
  const TransferResultRow({super.key, required this.transfer, this.onOpen});

  final FileTransferSnapshot transfer;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final issue = transferStatusHasIssue(transfer.status);
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
                  transfer.name,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: DesignTokens.spacingXxs),
                Text(
                  transfer.direction == .push
                      ? transfer.destination
                      : transfer.source,
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
              icon: const Icon(AppIcons.more),
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
