import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/content/cache_status_provider.dart';
import 'package:scrcpy_connect/core/content/content_cache_failure.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

bool isMediaCacheAdmissionFailure(Object? error) {
  final code = switch (error) {
    RequestFailure() => error.code,
    ContentCacheFailure() => error.code,
    _ => '$error'.split(':').first,
  };
  return const {
    'cache_budget_exceeded',
    'cache_space_unknown',
    'cache_capacity',
  }.contains(code);
}

/// 阻断处重新读取真实可回收量；清理仍由缓存所有者核验保护，页面不选择删除路径。
class MediaCacheBlocker extends HookConsumerWidget {
  const MediaCacheBlocker({super.key, this.onReduceSelection});
  final VoidCallback? onReduceSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(contentCacheControlProvider);
    bool ownsScope() =>
        context.mounted &&
        identical(ref.read(contentCacheControlProvider), cache);
    final busy = useValueNotifier(false, [cache]);
    useValueListenable(busy);
    final outcome = useValueNotifier<String?>(null, [cache]);
    useValueListenable(outcome);
    final status = ref.watch(cacheStatusProvider);
    final reclaimable = status.value?.reclaimableBytes ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.isLoading) const ContentLoadingIndicator(),
        if (status.hasError) const StateNote('暂时无法查看哪些文件可以清理。请检查本机存储空间后再试。'),
        if (status.hasValue && reclaimable == 0)
          const StateNote('目前没有可清理的临时文件。正在使用的文件会保留。'),
        if (reclaimable > 0)
          OutlinedButton(
            onPressed: busy.value
                ? null
                : () async {
                    if (!await confirm(
                          context,
                          '清理可回收暂存？',
                          '会清理本机已用完的临时文件。正在使用的文件和手机上的原文件会保留。',
                          action: '清理暂存',
                        ) ||
                        (!context.mounted || !ownsScope())) {
                      return;
                    }
                    busy.value = true;
                    try {
                      final deleted = await cache.clear();
                      if ((!context.mounted || !ownsScope())) return;
                      outcome.value = '已释放 ${bytes(deleted)}。你可以重试，或减少选择的文件数。';
                      ref.invalidate(cacheStatusProvider);
                    } catch (error) {
                      if (ownsScope()) {
                        outcome.value = failureMessage(
                          error,
                          fallback: '无法清理临时文件。请关闭正在使用的文件后再试。',
                        );
                      }
                    } finally {
                      if (ownsScope()) busy.value = false;
                    }
                  },
            child: Text(busy.value ? '正在清理…' : '清理可回收暂存'),
          ),
        if (outcome.value != null) StateNote(outcome.value!),
        if (onReduceSelection != null)
          TextButton(
            onPressed: busy.value ? null : onReduceSelection,
            child: const Text('返回减少选择'),
          ),
      ],
    );
  }
}

Future<void> showMediaCacheAdmissionFailure(
  BuildContext context,
  Object error, {
  bool canReduceSelection = false,
  VoidCallback? onOpenPhone,
}) => showAppDialog<void>(
  context: context,
  builder: (context) => AppAlertDialog(
    title: const Text('暂时无法准备原件'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(failureMessage(error, fallback: '无法准备临时文件。请检查本机存储空间。')),
          MediaCacheBlocker(
            onReduceSelection: canReduceSelection
                ? () => Navigator.pop(context)
                : null,
          ),
        ],
      ),
    ),
    actions: [
      if (onOpenPhone != null)
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onOpenPhone();
          },
          child: const Text('在手机上处理'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回'),
      ),
    ],
  ),
);
