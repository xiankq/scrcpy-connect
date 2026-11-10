import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.unplug,
                  size: DesignTokens.componentEmptyContentIconSize,
                ),
                const SizedBox(height: DesignTokens.spacingLg),
                Text(
                  '无法启动设备连接服务',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: DesignTokens.spacingSm),
                SelectableText(
                  error is StateError
                      ? (error as StateError).message.toString()
                      : error is FormatException
                      ? (error as FormatException).message
                      : '$error'.replaceFirst(
                          RegExp(r'^(?:Exception|Bad state):\s*'),
                          '',
                        ),
                ),
                const SizedBox(height: DesignTokens.spacingLg),
                FilledButton(onPressed: onRetry, child: const Text('重新启动')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
