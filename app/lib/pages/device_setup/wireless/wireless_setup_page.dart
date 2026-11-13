import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/pages/device_setup/wireless/models/wireless_setup_state.dart';
import 'package:scrcpy_connect/pages/device_setup/wireless/wireless_setup_notifier.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class WirelessSetupPage extends HookConsumerWidget {
  const WirelessSetupPage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = useMemoized(Object.new, [device.id]);
    final currentScope = useRef(scope)..value = scope;
    final provider = wirelessSetupProvider(deviceId: device.id, scope: scope);
    final state = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    final form = useMemoized(GlobalKey<FormState>.new);
    final port = useTextEditingController(text: '5555');
    final selected = useState<String?>(null);
    final selectionNotice = useState<String?>(null);
    bool current() =>
        context.mounted &&
        identical(currentScope.value, scope) &&
        identical(ref.read(provider.notifier), actions);
    final choice = state.addresses.any((item) => item.address == selected.value)
        ? selected.value
        : state.addresses.length == 1
        ? state.addresses.single.address
        : null;
    useEffect(() {
      Future.microtask(() {
        if (!current()) return;
        final addresses = ref.read(provider).addresses;
        if (addresses.any((item) => item.address == selected.value)) return;
        if (selected.value != null && !ref.read(provider).loading) {
          selectionNotice.value = '目标设备的网络地址已变化，请重新选择。';
        }
        selected.value = addresses.length == 1
            ? addresses.single.address
            : null;
      });
      return null;
    }, [state.addresses.map((item) => item.address).join(','), scope]);

    Future<void> submit() async {
      if (state.busy || state.loading || !form.currentState!.validate()) return;
      final currentDevice = ref
          .read(deviceListProvider.notifier)
          .current(device);
      if (currentDevice.status != DeviceConnectionStatus.connected) {
        await offerDeviceConnection(context, ref, currentDevice);
        return;
      }
      selectionNotice.value = null;
      final request = await actions.prepare(
        address: choice!,
        port: int.parse(port.text.trim()),
      );
      bool ownsConfirmation() =>
          current() && identical(ref.read(provider).confirmation, request);
      if (request == null || !context.mounted || !ownsConfirmation()) return;
      try {
        final accepted = await confirmConnectionChange(
          context,
          '切换并连接？',
          '将在当前授权设备上开启 ${request.port} 端口，再连接 ${request.address}。当前连接、画面和活动将中断；此方式不使用无线调试加密，仅在可信网络使用。验证成功后才更新设备记录。',
          action: '切换并连接',
        );
        if (accepted && ownsConfirmation()) await actions.submit(request);
      } finally {
        if (current()) actions.dismiss(request);
      }
    }

    return PageFrame(
      title: '转为 IP 连接',
      child: ConnectionContent(
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            ContentPanel(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '切换将中断当前连接及活动。仅在可信网络使用。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    if (state.loading) const ContentLoadingIndicator(),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${state.addresses.map((a) => a.address).join(',')}:$choice',
                      ),
                      initialValue: choice,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '目标设备网络地址'),
                      hint: Text(
                        state.addresses.isEmpty ? '暂无可用地址' : '选择目标设备的网络地址',
                      ),
                      items: [
                        for (final candidate in state.addresses)
                          DropdownMenuItem(
                            value: candidate.address,
                            child: Text(
                              '${candidate.address}${candidate.interface.isEmpty ? '' : ' · ${candidate.interface}'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged:
                          state.busy || state.loading || state.addresses.isEmpty
                          ? null
                          : (next) => selected.value = next,
                      validator: (next) =>
                          next == null ? '请选择此设备当前的网络地址' : null,
                    ),
                    if (!state.loading &&
                        state.error == null &&
                        state.addresses.isEmpty)
                      const StateNote('此设备当前没有可用的网络地址。连接网络后重新获取。'),
                    TextButton(
                      onPressed: state.busy || state.loading
                          ? null
                          : actions.refresh,
                      child: Text(state.loading ? '正在获取…' : '重新获取地址'),
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    TextFormField(
                      controller: port,
                      enabled: !state.busy,
                      validator: validatePort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '连接端口'),
                    ),
                    if (state.error != null) StateNote(state.error!),
                    if (state.notice != null) StateNote(state.notice!),
                    if (selectionNotice.value != null &&
                        selectionNotice.value != state.notice)
                      StateNote(selectionNotice.value!),
                    if (state.phase == WirelessSetupPhase.completed)
                      const StateNote('已转为 IP 连接'),
                    const SizedBox(height: DesignTokens.spacingSectionTitle),
                    FilledButton(
                      onPressed:
                          state.busy || state.loading || state.addresses.isEmpty
                          ? null
                          : submit,
                      child: Text(state.busy ? '正在切换…' : '切换并连接'),
                    ),
                    if (state.busy && state.canCancel)
                      TextButton(
                        onPressed: state.phase == WirelessSetupPhase.cancelling
                            ? null
                            : actions.cancel,
                        child: Text(switch (state.phase) {
                          WirelessSetupPhase.cancelling => '正在取消…',
                          WirelessSetupPhase.cleanupRequired => '重试取消',
                          _ => '取消本次切换',
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
