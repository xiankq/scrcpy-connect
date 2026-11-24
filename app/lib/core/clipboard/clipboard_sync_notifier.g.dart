// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'clipboard_sync_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 同步状态、计数和资源由同一个 scope 所有者维护。

@ProviderFor(ClipboardSyncNotifier)
final clipboardSyncProvider = ClipboardSyncNotifierProvider._();

/// 同步状态、计数和资源由同一个 scope 所有者维护。
final class ClipboardSyncNotifierProvider
    extends $NotifierProvider<ClipboardSyncNotifier, ClipboardSyncState> {
  /// 同步状态、计数和资源由同一个 scope 所有者维护。
  ClipboardSyncNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clipboardSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clipboardSyncNotifierHash();

  @$internal
  @override
  ClipboardSyncNotifier create() => ClipboardSyncNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipboardSyncState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipboardSyncState>(value),
    );
  }
}

String _$clipboardSyncNotifierHash() =>
    r'356ba503a7353a15a272cc4e529aa3519027428b';

/// 同步状态、计数和资源由同一个 scope 所有者维护。

abstract class _$ClipboardSyncNotifier extends $Notifier<ClipboardSyncState> {
  ClipboardSyncState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClipboardSyncState, ClipboardSyncState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClipboardSyncState, ClipboardSyncState>,
              ClipboardSyncState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
