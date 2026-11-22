import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:scrcpy_connect/widgets/app_session_scope.dart';

class AppSessionContent extends StatelessWidget {
  const AppSessionContent({
    super.key,
    this.title = '邻接',
    this.root = false,
    required this.child,
  });

  final String title;
  final bool root;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.maybeOf(context);
    if (session == null || session.ready) return child;
    return PageFrame(
      title: title,
      root: root,
      child: Builder(
        builder: (context) => ListView(
          padding:
              PageChromePadding.of(context) +
              const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            if (session.failure case final failure?) ...[
              StateNote(failure, icon: LucideIcons.circleAlert),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: session.onRetry,
                  child: const Text('重试'),
                ),
              ),
            ] else
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: ContentLoadingIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
