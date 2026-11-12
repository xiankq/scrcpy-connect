// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'device_query_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同一能力的设备读取共享连接事件筛选；每个查询独立持有取消令牌。

@ProviderFor(deviceDetails)
final deviceDetailsProvider = DeviceDetailsFamily._();

/// 同一能力的设备读取共享连接事件筛选；每个查询独立持有取消令牌。

final class DeviceDetailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceReading<DeviceDetails>>,
          DeviceReading<DeviceDetails>,
          FutureOr<DeviceReading<DeviceDetails>>
        >
    with
        $FutureModifier<DeviceReading<DeviceDetails>>,
        $FutureProvider<DeviceReading<DeviceDetails>> {
  /// 同一能力的设备读取共享连接事件筛选；每个查询独立持有取消令牌。
  DeviceDetailsProvider._({
    required DeviceDetailsFamily super.from,
    required (String, {String? connectionId}) super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceDetailsHash();

  @override
  String toString() {
    return r'deviceDetailsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<DeviceReading<DeviceDetails>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceReading<DeviceDetails>> create(Ref ref) {
    final argument = this.argument as (String, {String? connectionId});
    return deviceDetails(ref, argument.$1, connectionId: argument.connectionId);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceDetailsHash() => r'6901ccdc9c50e058d70e91578d5886cde3ddb6c7';

/// 同一能力的设备读取共享连接事件筛选；每个查询独立持有取消令牌。

final class DeviceDetailsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<DeviceReading<DeviceDetails>>,
          (String, {String? connectionId})
        > {
  DeviceDetailsFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 同一能力的设备读取共享连接事件筛选；每个查询独立持有取消令牌。

  DeviceDetailsProvider call(String deviceId, {String? connectionId}) =>
      DeviceDetailsProvider._(
        argument: (deviceId, connectionId: connectionId),
        from: this,
      );

  @override
  String toString() => r'deviceDetailsProvider';
}

@ProviderFor(deviceCapabilities)
final deviceCapabilitiesProvider = DeviceCapabilitiesFamily._();

final class DeviceCapabilitiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceCapabilities>,
          DeviceCapabilities,
          FutureOr<DeviceCapabilities>
        >
    with
        $FutureModifier<DeviceCapabilities>,
        $FutureProvider<DeviceCapabilities> {
  DeviceCapabilitiesProvider._({
    required DeviceCapabilitiesFamily super.from,
    required (String, {int revision}) super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceCapabilitiesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceCapabilitiesHash();

  @override
  String toString() {
    return r'deviceCapabilitiesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<DeviceCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceCapabilities> create(Ref ref) {
    final argument = this.argument as (String, {int revision});
    return deviceCapabilities(ref, argument.$1, revision: argument.revision);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceCapabilitiesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceCapabilitiesHash() =>
    r'5eaa83396dc9eb9ba68c5c67c5488e6e6165ec24';

final class DeviceCapabilitiesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<DeviceCapabilities>,
          (String, {int revision})
        > {
  DeviceCapabilitiesFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceCapabilitiesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DeviceCapabilitiesProvider call(String deviceId, {int revision = 0}) =>
      DeviceCapabilitiesProvider._(
        argument: (deviceId, revision: revision),
        from: this,
      );

  @override
  String toString() => r'deviceCapabilitiesProvider';
}

@ProviderFor(deviceDiagnosis)
final deviceDiagnosisProvider = DeviceDiagnosisFamily._();

final class DeviceDiagnosisProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceDiagnosis>,
          DeviceDiagnosis,
          FutureOr<DeviceDiagnosis>
        >
    with $FutureModifier<DeviceDiagnosis>, $FutureProvider<DeviceDiagnosis> {
  DeviceDiagnosisProvider._({
    required DeviceDiagnosisFamily super.from,
    required (String, {int revision}) super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceDiagnosisProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceDiagnosisHash();

  @override
  String toString() {
    return r'deviceDiagnosisProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<DeviceDiagnosis> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceDiagnosis> create(Ref ref) {
    final argument = this.argument as (String, {int revision});
    return deviceDiagnosis(ref, argument.$1, revision: argument.revision);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceDiagnosisProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceDiagnosisHash() => r'296ed793cb972980556e9dda397cc8e9cdbd0ff8';

final class DeviceDiagnosisFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<DeviceDiagnosis>,
          (String, {int revision})
        > {
  DeviceDiagnosisFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceDiagnosisProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DeviceDiagnosisProvider call(String deviceId, {int revision = 0}) =>
      DeviceDiagnosisProvider._(
        argument: (deviceId, revision: revision),
        from: this,
      );

  @override
  String toString() => r'deviceDiagnosisProvider';
}

@ProviderFor(installedDeviceApps)
final installedDeviceAppsProvider = InstalledDeviceAppsFamily._();

final class InstalledDeviceAppsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DeviceApp>>,
          List<DeviceApp>,
          FutureOr<List<DeviceApp>>
        >
    with $FutureModifier<List<DeviceApp>>, $FutureProvider<List<DeviceApp>> {
  InstalledDeviceAppsProvider._({
    required InstalledDeviceAppsFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'installedDeviceAppsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$installedDeviceAppsHash();

  @override
  String toString() {
    return r'installedDeviceAppsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<DeviceApp>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DeviceApp>> create(Ref ref) {
    final argument = this.argument as String;
    return installedDeviceApps(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is InstalledDeviceAppsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$installedDeviceAppsHash() =>
    r'26d88047cd57b589237abdfdab3c0ad9b2794197';

final class InstalledDeviceAppsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<DeviceApp>>, String> {
  InstalledDeviceAppsFamily._()
    : super(
        retry: _noRetry,
        name: r'installedDeviceAppsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  InstalledDeviceAppsProvider call(String deviceId) =>
      InstalledDeviceAppsProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'installedDeviceAppsProvider';
}

@ProviderFor(runningDeviceApps)
final runningDeviceAppsProvider = RunningDeviceAppsFamily._();

final class RunningDeviceAppsProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunningDeviceApps>,
          RunningDeviceApps,
          FutureOr<RunningDeviceApps>
        >
    with
        $FutureModifier<RunningDeviceApps>,
        $FutureProvider<RunningDeviceApps> {
  RunningDeviceAppsProvider._({
    required RunningDeviceAppsFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'runningDeviceAppsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runningDeviceAppsHash();

  @override
  String toString() {
    return r'runningDeviceAppsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<RunningDeviceApps> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RunningDeviceApps> create(Ref ref) {
    final argument = this.argument as String;
    return runningDeviceApps(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RunningDeviceAppsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runningDeviceAppsHash() => r'ef08f9fb21bef8403fbc43ade9c9eae23d4af5b1';

final class RunningDeviceAppsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RunningDeviceApps>, String> {
  RunningDeviceAppsFamily._()
    : super(
        retry: _noRetry,
        name: r'runningDeviceAppsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RunningDeviceAppsProvider call(String deviceId) =>
      RunningDeviceAppsProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'runningDeviceAppsProvider';
}

@ProviderFor(deviceAppIcon)
final deviceAppIconProvider = DeviceAppIconFamily._();

final class DeviceAppIconProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceAppIcon>,
          DeviceAppIcon,
          FutureOr<DeviceAppIcon>
        >
    with $FutureModifier<DeviceAppIcon>, $FutureProvider<DeviceAppIcon> {
  DeviceAppIconProvider._({
    required DeviceAppIconFamily super.from,
    required (DeviceAppIconTarget, {Object? revision}) super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceAppIconProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceAppIconHash();

  @override
  String toString() {
    return r'deviceAppIconProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<DeviceAppIcon> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceAppIcon> create(Ref ref) {
    final argument = this.argument as (DeviceAppIconTarget, {Object? revision});
    return deviceAppIcon(ref, argument.$1, revision: argument.revision);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceAppIconProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceAppIconHash() => r'faf1697cf7b51cbfdd1199a5696c065dc885ce65';

final class DeviceAppIconFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<DeviceAppIcon>,
          (DeviceAppIconTarget, {Object? revision})
        > {
  DeviceAppIconFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceAppIconProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DeviceAppIconProvider call(DeviceAppIconTarget target, {Object? revision}) =>
      DeviceAppIconProvider._(
        argument: (target, revision: revision),
        from: this,
      );

  @override
  String toString() => r'deviceAppIconProvider';
}

@ProviderFor(deviceCalls)
final deviceCallsProvider = DeviceCallsFamily._();

final class DeviceCallsProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceCallsSnapshot>,
          DeviceCallsSnapshot,
          FutureOr<DeviceCallsSnapshot>
        >
    with
        $FutureModifier<DeviceCallsSnapshot>,
        $FutureProvider<DeviceCallsSnapshot> {
  DeviceCallsProvider._({
    required DeviceCallsFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceCallsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceCallsHash();

  @override
  String toString() {
    return r'deviceCallsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<DeviceCallsSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceCallsSnapshot> create(Ref ref) {
    final argument = this.argument as String;
    return deviceCalls(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceCallsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceCallsHash() => r'655784e669b1d55005ae111e4fe3540c18d4d02a';

final class DeviceCallsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<DeviceCallsSnapshot>, String> {
  DeviceCallsFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceCallsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DeviceCallsProvider call(String deviceId) =>
      DeviceCallsProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'deviceCallsProvider';
}

@ProviderFor(deviceNotifications)
final deviceNotificationsProvider = DeviceNotificationsFamily._();

final class DeviceNotificationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceNotificationsSnapshot>,
          DeviceNotificationsSnapshot,
          FutureOr<DeviceNotificationsSnapshot>
        >
    with
        $FutureModifier<DeviceNotificationsSnapshot>,
        $FutureProvider<DeviceNotificationsSnapshot> {
  DeviceNotificationsProvider._({
    required DeviceNotificationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceNotificationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceNotificationsHash();

  @override
  String toString() {
    return r'deviceNotificationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<DeviceNotificationsSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceNotificationsSnapshot> create(Ref ref) {
    final argument = this.argument as String;
    return deviceNotifications(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceNotificationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceNotificationsHash() =>
    r'6f5f84a52aaa98d08c9e7af21237bc4895ff23b6';

final class DeviceNotificationsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<DeviceNotificationsSnapshot>,
          String
        > {
  DeviceNotificationsFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceNotificationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DeviceNotificationsProvider call(String deviceId) =>
      DeviceNotificationsProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'deviceNotificationsProvider';
}
