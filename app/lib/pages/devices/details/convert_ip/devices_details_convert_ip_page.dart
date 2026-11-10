import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceConvertIpPage extends HookWidget {
  const DeviceConvertIpPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppStore controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final form = useMemoized(GlobalKey<FormState>.new);
    final port = useTextEditingController(text: '5555');
    final addresses = useState<List<Json>>([]);
    final selected = useState<String?>(null);
    final loading = useState(false);
    final busy = useState(false);
    final requestStarted = useState(false);
    final error = useState<String?>(null);
    final notice = useState<String?>(null);
    final done = useState(false);
    final generation = useRef(0);
    final attempt = useRef<String?>(null);
    final deviceId = value(device, 'id');

    Future<Json?> readAddresses() async {
      final revision = ++generation.value;
      loading.value = true;
      error.value = null;
      try {
        final current = controller.currentDevice(device);
        if (current['status'] != 'connected') {
          throw const RequestFailure('disconnected', '请先连接此设备，再读取网络地址。');
        }
        final result = await controller.request('device.network.get', {
          'deviceId': deviceId,
        });
        if (!context.mounted || generation.value != revision) return null;
        final latest = controller.currentDevice(device);
        if (result['deviceId'] != deviceId ||
            value(result, 'connectionId').isEmpty ||
            latest['status'] != 'connected' ||
            (value(latest, 'connectionId').isNotEmpty &&
                result['connectionId'] != latest['connectionId'])) {
          throw const RequestFailure('connection_changed', '设备连接已变化，请重新获取地址。');
        }
        final candidates = <String, Json>{};
        for (final item in objects(result['addresses'])) {
          final address = value(item, 'address');
          if (address.isNotEmpty &&
              validateAddress(address) == null &&
              InternetAddress.tryParse(address.split('%').first) != null) {
            candidates.putIfAbsent(address, () => item);
          }
        }
        addresses.value = candidates.values.toList();
        if (!candidates.containsKey(selected.value)) {
          final changed = selected.value != null;
          selected.value = candidates.length == 1
              ? candidates.keys.single
              : null;
          if (changed) notice.value = '目标设备的网络地址已变化，请重新选择。';
        }
        return result;
      } catch (failure) {
        if (context.mounted && generation.value == revision) {
          addresses.value = [];
          selected.value = null;
          error.value = '$failure';
        }
        return null;
      } finally {
        if (context.mounted && generation.value == revision) {
          loading.value = false;
        }
      }
    }

    useEffect(() {
      Future.microtask(readAddresses);
      return () {
        generation.value++;
        final id = attempt.value;
        if (id != null) {
          controller.execute(ApplicationCommand.devicesCancel, {
            'attemptId': id,
          }).ignore();
        }
      };
    }, [deviceId]);

    Future<void> cancel() async {
      final id = attempt.value;
      if (id == null) return;
      try {
        await controller.execute(ApplicationCommand.devicesCancel, {
          'attemptId': id,
        });
        if (!context.mounted || attempt.value != id) return;
        attempt.value = null;
        generation.value++;
        loading.value = false;
        busy.value = false;
        requestStarted.value = false;
        notice.value = '已取消切换。调试服务可能已重启，请核对当前连接状态。';
        await controller.refreshDevices();
      } catch (failure) {
        if (context.mounted) error.value = '$failure';
      }
    }

    Future<void> submit() async {
      if (busy.value || loading.value || !form.currentState!.validate()) return;
      final current = controller.currentDevice(device);
      if (current['status'] != 'connected') {
        await offerDeviceConnection(context, controller, current);
        return;
      }
      final id = 'ip-${DateTime.now().microsecondsSinceEpoch}-$deviceId';
      attempt.value = id;
      final address = selected.value;
      final parsedPort = int.parse(port.text.trim());
      busy.value = true;
      done.value = false;
      notice.value = null;
      try {
        final network = await readAddresses();
        if (!context.mounted || network == null || attempt.value != id) return;
        if (selected.value != address ||
            !addresses.value.any((item) => item['address'] == address)) {
          notice.value = '目标设备的网络地址已变化，请重新选择。';
          return;
        }
        if (!await confirmConnectionChange(
              context,
              '切换并连接？',
              '将在当前授权设备上开启 $parsedPort 端口，再连接 $address。当前连接、画面和活动将中断；此方式不使用无线调试加密，仅在可信网络使用。验证成功后才更新设备记录。',
              action: '切换并连接',
            ) ||
            !context.mounted) {
          return;
        }
        if (attempt.value != id) return;
        requestStarted.value = true;
        final result = await controller.request('devices.wireless', {
          'deviceId': deviceId,
          'address': address,
          'port': parsedPort,
          'attemptId': id,
        });
        if (!context.mounted || attempt.value != id) return;
        if (result['enabled'] != true ||
            result['connected'] != true ||
            result['deviceId'] != deviceId) {
          throw const RequestFailure(
            'ip_switch_unverified',
            '尚未验证 IP 连接，请检查设备连接状态。',
          );
        }
        await controller.refreshDevices();
        if (context.mounted && attempt.value == id) done.value = true;
      } catch (failure) {
        await controller.refreshDevices();
        if (context.mounted && attempt.value == id) {
          error.value = '$failure';
          notice.value = '设备记录未确认更新，调试服务可能已重启，请核对连接状态。';
        }
      } finally {
        if (context.mounted && attempt.value == id) {
          busy.value = false;
          requestStarted.value = false;
          attempt.value = null;
        }
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
                    if (loading.value) const ContentLoadingIndicator(),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${addresses.value.map((a) => a['address']).join(',')}:${selected.value}',
                      ),
                      initialValue: selected.value,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '目标设备网络地址'),
                      hint: Text(
                        addresses.value.isEmpty ? '暂无可用地址' : '选择目标设备的网络地址',
                      ),
                      items: [
                        for (final candidate in addresses.value)
                          DropdownMenuItem(
                            value: value(candidate, 'address'),
                            child: Text(
                              '${value(candidate, 'address')}${value(candidate, 'interface').isEmpty ? '' : ' · ${value(candidate, 'interface')}'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged:
                          busy.value || loading.value || addresses.value.isEmpty
                          ? null
                          : (next) => selected.value = next,
                      validator: (next) =>
                          next == null ? '请选择此设备当前的网络地址' : null,
                    ),
                    if (!loading.value &&
                        error.value == null &&
                        addresses.value.isEmpty)
                      const StateNote('此设备当前没有可用的网络地址。连接网络后重新获取。'),
                    TextButton(
                      onPressed: busy.value || loading.value
                          ? null
                          : readAddresses,
                      child: Text(loading.value ? '正在获取…' : '重新获取地址'),
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    TextFormField(
                      controller: port,
                      enabled: !busy.value,
                      validator: validatePort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '连接端口'),
                    ),
                    if (error.value != null) StateNote(error.value!),
                    if (notice.value != null) StateNote(notice.value!),
                    if (done.value) const StateNote('已转为 IP 连接'),
                    const SizedBox(height: DesignTokens.spacingSectionTitle),
                    FilledButton(
                      onPressed:
                          busy.value || loading.value || addresses.value.isEmpty
                          ? null
                          : submit,
                      child: Text(busy.value ? '正在切换…' : '切换并连接'),
                    ),
                    if (busy.value && requestStarted.value)
                      TextButton(
                        onPressed: cancel,
                        child: const Text('取消本次切换'),
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
