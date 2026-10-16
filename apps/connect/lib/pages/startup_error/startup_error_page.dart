import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class StartupErrorPage extends StatelessWidget {
  const StartupErrorPage({
    super.key,
    required this.error,
    required this.onRetry,
  });
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.unplug, size: 48),
              const SizedBox(height: 24),
              const Text('无法启动设备连接服务', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 12),
              SelectableText('$error'),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('重新启动')),
            ],
          ),
        ),
      ),
    ),
  );
}
