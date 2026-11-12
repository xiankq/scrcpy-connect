import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class ConnectionAddressFields extends StatelessWidget {
  const ConnectionAddressFields({
    super.key,
    required this.address,
    required this.port,
    required this.pairingCode,
    required this.pairing,
    required this.completingPairing,
    required this.legacyTcp,
    required this.enabled,
    required this.onAddressChanged,
  });

  final TextEditingController address;
  final TextEditingController port;
  final TextEditingController pairingCode;
  final bool pairing;
  final bool completingPairing;
  final bool legacyTcp;
  final bool enabled;
  final ValueChanged<String> onAddressChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pairing) ...[
          Text(
            '在手机的“开发者选项 → 无线调试 → 使用配对码配对”中查看配对信息，填写后即可连接。',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
        ],
        if (!pairing) ...[
          if (completingPairing) ...[
            Text('已配对，尚未连接', style: textTheme.bodyMedium),
            const SizedBox(height: DesignTokens.spacingXs),
          ],
          Text(
            legacyTcp
                ? '已有调试授权：先通过 USB 允许按地址连接，仅在可信网络使用。'
                : '使用手机无线调试主页面的连接端口。',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: DesignTokens.spacingMd),
        ],
        TextFormField(
          style: textTheme.bodyMedium,
          controller: address,
          onChanged: onAddressChanged,
          validator: validateAddress,
          enabled: enabled,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'IP 地址或主机名',
            hintText: '192.168.1.8',
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        TextFormField(
          style: textTheme.bodyMedium,
          controller: port,
          validator: validatePort,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: pairing ? '配对端口' : '连接端口',
            helperText: pairing
                ? '配对窗口中的端口'
                : legacyTcp
                ? null
                : '无线调试主页面中的端口',
          ),
        ),
        if (pairing) ...[
          const SizedBox(height: DesignTokens.spacingMd),
          TextFormField(
            style: textTheme.bodyMedium,
            controller: pairingCode,
            enabled: enabled,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: (value) =>
                RegExp(r'^\d{6}$').hasMatch(value ?? '') ? null : '请输入六位配对码',
            decoration: const InputDecoration(labelText: '配对码'),
          ),
        ],
      ],
    );
  }
}
