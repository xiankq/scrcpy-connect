import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class GalleryScopeSheet extends StatelessWidget {
  const GalleryScopeSheet({
    super.key,
    required this.device,
    required this.snapshot,
  });
  final Json device;
  final Json snapshot;

  @override
  Widget build(BuildContext context) {
    final issues = objects(snapshot['issues']);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('本次检查范围', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: DesignTokens.spacingSm),
              Text('${deviceName(device)} · ${snapshot['total'] ?? 0} 项结果'),
              const SizedBox(height: DesignTokens.spacingSm),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const StateNote(
                            '检查当前手机共享存储中的照片与视频，包含下载和自定义文件夹；按文件扩展名识别，文件修改时间不等于拍摄时间。',
                          ),
                          StateNote(
                            '范围：${strings(jsonObject(snapshot['scope'])['roots']).join('、')}\n不包含：${strings(jsonObject(snapshot['scope'])['excluded']).join('、')}',
                          ),
                          const StateNote(
                            '结果是本次检查的快照，手机内容可能随后变化。下拉重新检查会生成新结果；打开和保存时再次核验原件。',
                          ),
                          if (issues.isNotEmpty)
                            Text(
                              '未完整检查 · ${snapshot['issueCount'] ?? issues.length} 处',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                        ],
                      ),
                    ),
                    SliverList.builder(
                      itemCount: issues.length,
                      itemBuilder: (context, index) {
                        final issue = issues[index];
                        final code = value(issue, 'code');
                        final reason = code.endsWith('_limit')
                            ? '本次检查达到可处理范围，部分内容尚未列出；可在手机原应用继续查看。'
                            : value(issue, 'reason');
                        return StateNote(
                          '${value(issue, 'path')}\n$reason',
                          icon: LucideIcons.folderLock,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭范围'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
