import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

class ConnectionAddressFields extends StatelessWidget {
  const ConnectionAddressFields({
    super.key,
    required this.address,
    required this.port,
    required this.pairingCode,
    required this.focus,
    required this.pairing,
    required this.legacyTcp,
    required this.enabled,
    required this.onAddressChanged,
  });

  final TextEditingController address;
  final TextEditingController port;
  final TextEditingController pairingCode;
  final ({FocusNode address, FocusNode port, FocusNode pairingCode}) focus;
  final bool pairing;
  final bool legacyTcp;
  final bool enabled;
  final ValueChanged<String> onAddressChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const contentPadding = EdgeInsets.all(
      DesignTokens.componentConnectionFieldPadding,
    );
    final addressField = _labelled(
      context,
      pairing ? '手机地址' : 'IP 地址或主机名',
      TextFormField(
        key: ValueKey(focus.address),
        focusNode: focus.address,
        style: textTheme.bodyMedium,
        controller: address,
        onChanged: onAddressChanged,
        validator: validateAddress,
        enabled: enabled,
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: '192.168.1.8',
          contentPadding: contentPadding,
        ),
      ),
    );
    final portField = _labelled(
      context,
      pairing ? '配对端口' : '连接端口',
      TextFormField(
        key: ValueKey(focus.port),
        focusNode: focus.port,
        style: textTheme.bodyMedium,
        controller: port,
        validator: validatePort,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(contentPadding: contentPadding),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            return constraints.maxWidth < 275 * scale
                ? Column(
                    children: [
                      addressField,
                      const SizedBox(height: DesignTokens.spacingMd),
                      portField,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: addressField),
                      const SizedBox(width: DesignTokens.spacingSm),
                      Expanded(child: portField),
                    ],
                  );
          },
        ),
        if (pairing) ...[
          const SizedBox(height: DesignTokens.spacingLg),
          _labelled(
            context,
            '六位配对码',
            TextFormField(
              key: ValueKey(focus.pairingCode),
              focusNode: focus.pairingCode,
              style: textTheme.bodyMedium?.copyWith(
                letterSpacing: DesignTokens.spacingXs,
              ),
              controller: pairingCode,
              enabled: enabled,
              keyboardType: TextInputType.number,
              maxLength: 6,
              validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                  ? null
                  : '请输入手机上显示的 6 位配对码',
              decoration: const InputDecoration(
                counterText: '',
                contentPadding: contentPadding,
              ),
            ),
          ),
        ],
        const SizedBox(height: DesignTokens.spacingLg),
        Text(
          pairing
              ? '在手机的无线调试中选择「使用配对码配对」。'
              : legacyTcp
              ? '仅连接已授权的手机。请输入当前连接地址，并在可信网络使用。'
              : '使用手机无线调试主页面的连接地址和端口。',
          style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _labelled(BuildContext context, String label, Widget field) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      const SizedBox(height: DesignTokens.spacingXs),
      Semantics(label: label, child: field),
    ],
  );
}
