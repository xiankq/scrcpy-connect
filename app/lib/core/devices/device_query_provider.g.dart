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

String _$deviceDetailsHash() => r'e27a07305cdd6ae64995b22f30a31c6dc3d57a1f';

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
    r'd875133773ad0c28edec3bd672697df3cd2e78db';

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

String _$deviceDiagnosisHash() => r'1f70823c937629ca9905ec4f43a9d8911f79cd21';

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
    r'fd857708c10cee1effb7d56313484ad24902a5fc';

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

String _$runningDeviceAppsHash() => r'866f1e5f88f6969bc992202b855a84db1c700d84';

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

String _$deviceAppIconHash() => r'3e3b89a2130b94ca3a250d7771ae25039e1e22e2';

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

@ProviderFor(deviceCallsSnapshot)
final deviceCallsSnapshotProvider = DeviceCallsSnapshotFamily._();

final class DeviceCallsSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceCallsSnapshot>,
          DeviceCallsSnapshot,
          FutureOr<DeviceCallsSnapshot>
        >
    with
        $FutureModifier<DeviceCallsSnapshot>,
        $FutureProvider<DeviceCallsSnapshot> {
  DeviceCallsSnapshotProvider._({
    required DeviceCallsSnapshotFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceCallsSnapshotProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceCallsSnapshotHash();

  @override
  String toString() {
    return r'deviceCallsSnapshotProvider'
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
    return deviceCallsSnapshot(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceCallsSnapshotProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceCallsSnapshotHash() =>
    r'd47195a8aebf86192be7628e1fa73b2fe5a0642d';

final class DeviceCallsSnapshotFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<DeviceCallsSnapshot>, String> {
  DeviceCallsSnapshotFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceCallsSnapshotProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DeviceCallsSnapshotProvider call(String deviceId) =>
      DeviceCallsSnapshotProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'deviceCallsSnapshotProvider';
}

@ProviderFor(deviceNotificationsSnapshot)
final deviceNotificationsSnapshotProvider =
    DeviceNotificationsSnapshotFamily._();

final class DeviceNotificationsSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceNotificationsSnapshot>,
          DeviceNotificationsSnapshot,
          FutureOr<DeviceNotificationsSnapshot>
        >
    with
        $FutureModifier<DeviceNotificationsSnapshot>,
        $FutureProvider<DeviceNotificationsSnapshot> {
  DeviceNotificationsSnapshotProvider._({
    required DeviceNotificationsSnapshotFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'deviceNotificationsSnapshotProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deviceNotificationsSnapshotHash();

  @override
  String toString() {
    return r'deviceNotificationsSnapshotProvider'
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
    return deviceNotificationsSnapshot(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceNotificationsSnapshotProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deviceNotificationsSnapshotHash() =>
    r'ca2c6a7582be2374edf1bb7d1941b2b76d57f259';

final class DeviceNotificationsSnapshotFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<DeviceNotificationsSnapshot>,
          String
        > {
  DeviceNotificationsSnapshotFamily._()
    : super(
        retry: _noRetry,
        name: r'deviceNotificationsSnapshotProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DeviceNotificationsSnapshotProvider call(String deviceId) =>
      DeviceNotificationsSnapshotProvider._(argument: deviceId, from: this);

  @override
  String toString() => r'deviceNotificationsSnapshotProvider';
}
