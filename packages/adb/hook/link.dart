import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:record_use/record_use.dart';

void main(List<String> args) async {
  await link(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final uses = input.recordedUses;
    // Without compiler reachability information retain the independent SDK.
    // A composed host supplies its own bindings and never initializes this SDK.
    const initialize = Method(
      'initializeNativeAdb',
      Library('package:adb/src/native/initialize.dart'),
    );
    if (uses == null || (uses.calls[initialize]?.isNotEmpty ?? false)) {
      output.assets.code.addAll(input.assets.code);
    }
  });
}
