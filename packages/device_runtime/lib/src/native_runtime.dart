import 'dart:io';
import 'dart:convert';

import 'package:flutter_adb/flutter_adb.dart';

import 'package:device_connections/device_connections.dart';
import 'package:device_preferences/device_preferences.dart';
import 'package:device_protocol/device_protocol.dart' show InteropException;

import 'preferences_runtime.dart';
import 'native_adb_adapter.dart';

import 'bundled_servers.dart';
import 'rust/api.dart' as core;

/// Retains the process owner until cleanup has actually succeeded. A failed
/// close can be retried, while another initialization cannot adopt that host.
class NativeAdbHostOwner {
  Future<FlutterAdb>? pending;
  Future<void>? _closing;
  bool closingRequested = false;

  Future<void> close() {
    if (_closing case final operation?) return operation;
    final operation = _close().whenComplete(() => _closing = null);
    _closing = operation;
    return operation;
  }

  Future<void> _close() async {
    final current = pending;
    if (current == null) return;
    closingRequested = true;
    await (await current).close();
    if (identical(pending, current)) pending = null;
    closingRequested = false;
  }
}

/// Shares a shutdown attempt and remembers completion. Failed attempts retain
/// their resource owners and may be retried by the application exit handler.
class NativeRuntimeShutdown {
  Future<void>? _operation;

  Future<void> run(Future<void> Function() shutdown) {
    if (_operation case final operation?) return operation;
    final operation = Future<void>.sync(shutdown)
        .catchError((Object error, StackTrace stack) {
          _operation = null;
          Error.throwWithStackTrace(error, stack);
        });
    _operation = operation;
    return operation;
  }
}

final _adbOwner = NativeAdbHostOwner();
String? _adbDirectory;
DevicePreferences? _preferences;
bool _nativeAdbBound = false;
String? _nativePolicyJson;

DevicePreferences get nativePreferences =>
    _preferences ??
    (throw StateError('Native preferences are not initialized'));

/// Prepares Flutter package assets before attaching the native runtime.
Future<void> initializeNativeRuntime({
  required String dataDirectory,
  ConnectionPolicy connectionPolicy = const ConnectionPolicy(),
  Directory? adbBinaryDirectory,
}) async {
  if (_adbOwner.closingRequested) {
    throw StateError('Native ADB shutdown must complete before initialization');
  }
  final policyJson = jsonEncode(connectionPolicy.toJson());
  if (_nativePolicyJson != null && _nativePolicyJson != policyJson) {
    throw const InteropException(
      'runtime_connection_policy_mismatch',
      '互联核心正在使用另一套连接策略，请重新启动应用。',
    );
  }
  if (Platform.isAndroid) {
    await BundledServers().prepare(Directory(dataDirectory));
  }
  if (_adbDirectory != null && _adbDirectory != dataDirectory) {
    throw StateError(
      'Native ADB host is already attached to another data directory',
    );
  }
  _adbDirectory = dataDirectory;
  FlutterAdb? host;
  final creating = _adbOwner.pending == null;
  try {
    _preferences ??= await PreferencesRuntime.prepare(Directory(dataDirectory));
    host = await (_adbOwner.pending ??= FlutterAdb.prepare(
      dataDirectory: Directory(dataDirectory),
      binaryDirectory: adbBinaryDirectory,
    ));
    final policy = connectionPolicy.toNativeJson();
    if (host.nativeConfiguration case final configuration?) {
      policy['adbServer'] = configuration;
    }
    await core.initialize(
      dataDirectory: dataDirectory,
      connectionPolicyJson: jsonEncode(policy),
      settingsDefaultsJson: jsonEncode(
        _preferences!.schema.executionMirror(_preferences!.current.toMap()),
      ),
    );
    if (!_nativeAdbBound) {
      host.bindNative(const NativeAdbAdapter());
      _nativeAdbBound = true;
    }
    _nativePolicyJson = policyJson;
  } catch (_) {
    if (creating) {
      if (host == null) {
        // A preparation failure returned no owner to attach. FlutterAdb owns
        // termination of its partial child before that future completes.
        _adbOwner.pending = null;
      } else {
        await _adbOwner.close();
      }
      _adbDirectory = null;
      _preferences = null;
      _nativeAdbBound = false;
      _nativePolicyJson = null;
    }
    rethrow;
  }
}

/// The runtime assembles this capability; its public contract is flutter_adb.
Future<AdbClient> nativeAdbClient() async {
  if (_adbOwner.closingRequested) {
    throw StateError('Native ADB host is shutting down');
  }
  final host = _adbOwner.pending;
  if (host == null) throw StateError('Native runtime is not initialized');
  return (await host).client;
}

/// Call after native device activities have been stopped during host exit.
Future<void> shutdownNativeAdb() async {
  await _adbOwner.close();
  _adbDirectory = null;
  _preferences = null;
  _nativeAdbBound = false;
  _nativePolicyJson = null;
}
