// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'qr_pairing_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(QrPairingNotifier)
final qrPairingProvider = QrPairingNotifierFamily._();

final class QrPairingNotifierProvider
    extends $NotifierProvider<QrPairingNotifier, QrPairingState> {
  QrPairingNotifierProvider._({
    required QrPairingNotifierFamily super.from,
    required ({String? deviceId, Object scope}) super.argument,
  }) : super(
         retry: null,
         name: r'qrPairingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$qrPairingNotifierHash();

  @override
  String toString() {
    return r'qrPairingProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  QrPairingNotifier create() => QrPairingNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(QrPairingState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<QrPairingState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is QrPairingNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$qrPairingNotifierHash() => r'd6ad17b88c4ae1612df8083a15745ae249ae96e1';

final class QrPairingNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          QrPairingNotifier,
          QrPairingState,
          QrPairingState,
          QrPairingState,
          ({String? deviceId, Object scope})
        > {
  QrPairingNotifierFamily._()
    : super(
        retry: null,
        name: r'qrPairingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  QrPairingNotifierProvider call({String? deviceId, required Object scope}) =>
      QrPairingNotifierProvider._(
        argument: (deviceId: deviceId, scope: scope),
        from: this,
      );

  @override
  String toString() => r'qrPairingProvider';
}

abstract class _$QrPairingNotifier extends $Notifier<QrPairingState> {
  late final _$args = ref.$arg as ({String? deviceId, Object scope});
  String? get deviceId => _$args.deviceId;
  Object get scope => _$args.scope;

  QrPairingState build({String? deviceId, required Object scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<QrPairingState, QrPairingState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<QrPairingState, QrPairingState>,
              QrPairingState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(deviceId: _$args.deviceId, scope: _$args.scope),
    );
  }
}
