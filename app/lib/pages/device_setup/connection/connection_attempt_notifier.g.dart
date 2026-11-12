// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'connection_attempt_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 一次手动连接的执行状态；页面持有表单、确认及导航。

@ProviderFor(ConnectionAttemptNotifier)
final connectionAttemptProvider = ConnectionAttemptNotifierFamily._();

/// 一次手动连接的执行状态；页面持有表单、确认及导航。
final class ConnectionAttemptNotifierProvider
    extends
        $NotifierProvider<ConnectionAttemptNotifier, ConnectionAttemptState> {
  /// 一次手动连接的执行状态；页面持有表单、确认及导航。
  ConnectionAttemptNotifierProvider._({
    required ConnectionAttemptNotifierFamily super.from,
    required Object super.argument,
  }) : super(
         retry: null,
         name: r'connectionAttemptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$connectionAttemptNotifierHash();

  @override
  String toString() {
    return r'connectionAttemptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ConnectionAttemptNotifier create() => ConnectionAttemptNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionAttemptState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionAttemptState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConnectionAttemptNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$connectionAttemptNotifierHash() =>
    r'a842c12634139d87c7f1be405d981d9329757011';

/// 一次手动连接的执行状态；页面持有表单、确认及导航。

final class ConnectionAttemptNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          ConnectionAttemptNotifier,
          ConnectionAttemptState,
          ConnectionAttemptState,
          ConnectionAttemptState,
          Object
        > {
  ConnectionAttemptNotifierFamily._()
    : super(
        retry: null,
        name: r'connectionAttemptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 一次手动连接的执行状态；页面持有表单、确认及导航。

  ConnectionAttemptNotifierProvider call({required Object scope}) =>
      ConnectionAttemptNotifierProvider._(argument: scope, from: this);

  @override
  String toString() => r'connectionAttemptProvider';
}

/// 一次手动连接的执行状态；页面持有表单、确认及导航。

abstract class _$ConnectionAttemptNotifier
    extends $Notifier<ConnectionAttemptState> {
  late final _$args = ref.$arg as Object;
  Object get scope => _$args;

  ConnectionAttemptState build({required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ConnectionAttemptState, ConnectionAttemptState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConnectionAttemptState, ConnectionAttemptState>,
              ConnectionAttemptState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(scope: _$args));
  }
}
