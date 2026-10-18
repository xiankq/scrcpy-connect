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
  final Future<void> Function(String directory) initializeRuntime;
  Future<void>? _running;
  String? _directory;

  Future<void> attach(String directory) {
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
    return _running = _initialize(directory)
        .whenComplete(() => _running = null);
  }

  Future<void> _initialize(String directory) async {
    if (!bindingsInitialized()) await initializeBindings();
    await initializeRuntime(directory);
  }
}
