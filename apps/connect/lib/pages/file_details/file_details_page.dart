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
    subtitle: deviceName(device),
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const FeatureIcon(
          LucideIcons.file,
          color: ConnectTokens.amber,
          size: 72,
        ),
        const SizedBox(height: 24),
        Text(
          value(file, 'name'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text('${bytes(file['size'])}\n${value(file, 'path')}'),
        if (!fileCanOpen(file))
          StateNote(fileUnavailableReason(file), icon: LucideIcons.circleAlert),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: fileCanOpen(file)
              ? () => retrieveFile(context, controller, device, file)
              : null,
          icon: const Icon(LucideIcons.download, size: 18),
          label: const Text('取回原文件'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: fileCanOpen(file)
              ? () =>
                    retrieveFile(context, controller, device, file, share: true)
              : null,
          icon: const Icon(LucideIcons.share2, size: 18),
          label: const Text('交给系统分享'),
        ),
        const StateNote('取回后可在本机编辑副本；修改后需要主动重新发送，不会自动回写手机。'),
      ],
    ),
  );
}
