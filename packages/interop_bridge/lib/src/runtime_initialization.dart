import 'dart:convert';

import 'connection_policy.dart';
import 'interop_exception.dart';

/// Owns process binding initialization independently of a UI attachment.
/// Releasing a bridge does not unload the Rust runtime or its authorization
/// identity. A new attachment reuses them and may never change their directory.
class RuntimeInitialization {
  RuntimeInitialization({
    required this.bindingsInitialized,
    required this.initializeBindings,
    required this.initializeRuntime,
  });

  final bool Function() bindingsInitialized;
  final Future<void> Function() initializeBindings;
  final Future<void> Function(String directory, ConnectionPolicy policy)
  initializeRuntime;
  Future<void>? _running;
  String? _directory;
  String? _policyJson;

  Future<void> attach(
    String directory, {
    ConnectionPolicy connectionPolicy = const ConnectionPolicy(),
  }) {
    final policyJson = jsonEncode(connectionPolicy.toJson());
    if (_policyJson != null && _policyJson != policyJson) {
      return Future.error(
        const InteropException(
          'runtime_connection_policy_mismatch',
          '互联核心已使用另一套连接策略，请重新启动应用。',
        ),
      );
    }
    if (_directory != null && _directory != directory) {
      return Future.error(
        const InteropException(
          'runtime_directory_mismatch',
          '互联核心已使用另一个私有目录，请重新启动应用。',
        ),
      );
    }
    if (_running case final existing?) return existing;
    _directory = directory;
    _policyJson = policyJson;
    return _running = _initialize(
      directory,
      connectionPolicy,
    ).whenComplete(() => _running = null);
  }

  Future<void> _initialize(String directory, ConnectionPolicy policy) async {
    if (!bindingsInitialized()) await initializeBindings();
    await initializeRuntime(directory, policy);
  }
}
