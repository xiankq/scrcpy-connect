import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/activities/activities_provider.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/activities/activity_management_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

/// 页面内容内距：左右 16（design.md「页面结构」）。
const _contentPadding = EdgeInsets.symmetric(
  horizontal: DesignTokens.componentPagePadding,
);

class ActivitiesPage extends HookConsumerWidget {
  const ActivitiesPage({super.key, required this.deviceId});
  final String deviceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final management = ref.watch(activityManagementProvider);
    final device =
        ref
            .watch(deviceListProvider)
            .devices
            .where((item) => item.id == deviceId)
            .firstOrNull ??
        DeviceSnapshot(id: deviceId);
    bool ownsScope() =>
        context.mounted &&
        identical(ref.read(activityManagementProvider), management);
    final provider = activitiesProvider(deviceId: deviceId);
    final query = ref.watch(provider);
    Future<void> refresh() => ref
        .refresh(provider.future)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return PageFrame(
      title: '当前活动',
      child: AsyncContent<ActivityCollection>(
        loadingPlaceholder: GroupedListView(
          padding: _contentPadding,
          children: [
            WorkspaceCallCard(device: device),
            const SkeletonRows(lines: 1, trailing: true),
          ],
        ),
        loading: query.isLoading,
        data: query.value,
        error: query.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取活动',
        builder: (context, data) {
          final unresolved = data.pendingApplications;
          final unresolvedIds = unresolved
              .map((item) => item.sessionId)
              .toSet();
          final activities = data.activities
              .where(
                (activity) =>
                    activity.target is! SessionActivityTarget ||
                    !unresolvedIds.contains(
                      (activity.target as SessionActivityTarget).sessionId,
                    ),
              )
              .toList();
          if (activities.isEmpty && unresolved.isEmpty) {
            return GroupedListView(
              padding: _contentPadding,
              children: [
                WorkspaceCallCard(device: device),
                EmptyContent(
                  icon: LucideIcons.activity,
                  title: '暂无正在进行的活动',
                  action: AppButton(
                    role: AppButtonRole.secondaryOnPage,
                    size: AppButtonSize.section,
                    onPressed: refresh,
                    label: '重新检查',
                  ),
                ),
              ],
            );
          }
          final colors = AppColors.of(context);
          final type = AppTypography.of(context);
          return GroupedListView(
            padding: _contentPadding,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.componentListHeaderPadding,
                ),
                child: Text(
                  activities.firstOrNull?.deviceName ?? '此设备',
                  style: type.footnote.copyWith(color: colors.textSecondary),
                ),
              ),
              WorkspaceCallCard(device: device),
              if (unresolved.isNotEmpty) ...[
                const SectionTitle('待核对'),
                for (final (index, session) in unresolved.indexed) ...[
                  if (index > 0) const SizedBox(height: DesignTokens.spacingMd),
                  _PendingLaunch(
                    deviceId: deviceId,
                    session: session,
                    refresh: refresh,
                  ),
                ],
              ],
              if (activities.isNotEmpty) ...[
                const SectionTitle('正在进行'),
                SettingsGroup(
                  children: [
                    for (final activity in activities)
                      ActionRow(
                        key: ValueKey(activity.target),
                        icon: LucideIcons.activity,
                        color: FunctionTone.connection,
                        title: activity.name,
                        trailing: Tooltip(
                          message: statusText(activity.status),
                          child: AppButton(
                            size: AppButtonSize.section,
                            onPressed: () async {
                              if (await confirm(
                                    context,
                                    '停止“${activity.name}”？',
                                    activity.stopImpact,
                                    action: '停止活动',
                                  ) &&
                                  context.mounted &&
                                  ownsScope()) {
                                await performAction(
                                  context,
                                  () =>
                                      management.stopActivity(activity.target),
                                );
                                if (ownsScope()) refresh();
                              }
                            },
                            label: '停止',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PendingLaunch extends HookConsumerWidget {
  const _PendingLaunch({
    required this.deviceId,
    required this.session,
    required this.refresh,
  });
  final String deviceId;
  final SessionActivity session;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final management = ref.watch(activityManagementProvider);
    final busy = useValueNotifier(false, [
      management,
      deviceId,
      session.sessionId,
    ]);
    useValueListenable(busy);
    bool ownsScope() =>
        context.mounted &&
        identical(ref.read(activityManagementProvider), management);
    Future<void> run(Future<void> Function() operation) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await operation();
      } catch (error) {
        if (context.mounted && ownsScope()) {
          feedback(
            context,
            failureMessage(error, fallback: '暂时无法确认窗口是否已关闭。请先查看窗口状态。'),
          );
        }
      } finally {
        if (ownsScope()) busy.value = false;
      }
    }

    final id = session.sessionId;
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    // 待核对的打开记录：一张 `card`（圆角 16、内距 16），标题、说明与两个区块按钮。
    return Material(
      color: colors.card,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(DesignTokens.componentCardRounded),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.componentCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.name, style: type.headline),
            const SizedBox(height: DesignTokens.spacingXs),
            Text(
              '暂时无法确认应用是否已打开。请先查看手机屏幕。',
              style: type.subheadline.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Wrap(
              spacing: DesignTokens.spacingSm,
              runSpacing: DesignTokens.spacingSm,
              children: [
                AppButton(
                  size: AppButtonSize.section,
                  onPressed: busy.value
                      ? null
                      : () => run(() async {
                          final result = await management.readActivities(
                            deviceId: deviceId,
                          );
                          if (!context.mounted || !ownsScope()) return;
                          final linked = session.linkedSessionId ?? id;
                          final pendingIds = result.pendingApplications
                              .map((item) => item.sessionId)
                              .toSet();
                          final live = result.activities
                              .where(
                                (item) =>
                                    item.target is SessionActivityTarget &&
                                    (item.target as SessionActivityTarget)
                                            .sessionId ==
                                        linked &&
                                    !pendingIds.contains(linked) &&
                                    !const {
                                      'failed',
                                      'stopped',
                                      'error',
                                    }.contains(item.status),
                              )
                              .firstOrNull;
                          if (ownsScope()) refresh();
                          if (live != null) {
                            await openRemoteRoute(
                              context,
                              deviceId: deviceId,
                              sessionId: (live.target as SessionActivityTarget)
                                  .sessionId,
                            );
                          } else {
                            feedback(context, '本次打开仍待核对，请在手机检查。未重新发送打开请求。');
                          }
                        }),
                  label: '重新核对',
                ),
                AppButton(
                  role: AppButtonRole.destructive,
                  size: AppButtonSize.section,
                  onPressed: busy.value
                      ? null
                      : () => run(() async {
                          if (!await confirm(
                                context,
                                '关闭本次打开记录？',
                                '仅结束本次跟踪及所属捕获，手机上的应用任务保留。之后重新打开可能迁移现有任务。',
                                action: '关闭记录',
                              ) ||
                              !context.mounted ||
                              !ownsScope()) {
                            return;
                          }
                          await management.stopActivity(
                            ActivityTarget.session(id),
                          );
                          if (ownsScope()) refresh();
                        }),
                  label: '关闭记录',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
