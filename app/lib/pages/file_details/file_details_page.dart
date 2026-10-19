import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_actions.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FileDetailsPage extends StatelessWidget {
  const FileDetailsPage({
    super.key,
    required this.controller,
    required this.device,
    required this.file,
  });
  final AppController controller;
  final Json device;
  final Json file;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: value(file, 'name'),
    child: GroupedListView(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      children: [
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('大小'),
                  const SizedBox(width: DesignTokens.spacingSm),
                  Expanded(
                    child: Text(bytes(file['size']), textAlign: TextAlign.end),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              SelectableText(value(file, 'path')),
            ],
          ),
        ),
        if (!fileCanOpen(file))
          StateNote(fileUnavailableReason(file), icon: LucideIcons.circleAlert),
        const SizedBox(height: DesignTokens.spacingLg),
        FilledButton.icon(
          onPressed: fileCanOpen(file)
              ? () => retrieveFile(context, controller, device, file)
              : null,
          icon: const Icon(
            LucideIcons.download,
            size: DesignTokens.componentIconActionSize,
          ),
          label: const Text('取回原文件'),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        OutlinedButton.icon(
          onPressed: fileCanOpen(file)
              ? () =>
                    retrieveFile(context, controller, device, file, share: true)
              : null,
          icon: const Icon(
            LucideIcons.share2,
            size: DesignTokens.componentIconActionSize,
          ),
          label: const Text('交给系统分享'),
        ),
        const StateNote('取回后可在本机编辑副本；修改后需要主动重新发送，不会自动回写手机。'),
      ],
    ),
  );
}
