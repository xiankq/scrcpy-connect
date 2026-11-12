// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'preferences_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 偏好投影与串行写入的唯一所有者；权威事件作废旧写入回执。

@ProviderFor(PreferencesNotifier)
final preferencesProvider = PreferencesNotifierProvider._();

/// 偏好投影与串行写入的唯一所有者；权威事件作废旧写入回执。
final class PreferencesNotifierProvider
    extends $NotifierProvider<PreferencesNotifier, PreferencesState> {
  /// 偏好投影与串行写入的唯一所有者；权威事件作废旧写入回执。
  PreferencesNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'preferencesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$preferencesNotifierHash();

  @$internal
  @override
  PreferencesNotifier create() => PreferencesNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PreferencesState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PreferencesState>(value),
    );
  }
}

String _$preferencesNotifierHash() =>
    r'9e60c773612ab6e8abfb585ff4f8532d762b1f1f';

/// 偏好投影与串行写入的唯一所有者；权威事件作废旧写入回执。

abstract class _$PreferencesNotifier extends $Notifier<PreferencesState> {
  PreferencesState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PreferencesState, PreferencesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PreferencesState, PreferencesState>,
              PreferencesState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
