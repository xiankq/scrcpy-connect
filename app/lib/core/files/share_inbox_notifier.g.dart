// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'share_inbox_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ShareInboxNotifier)
final shareInboxProvider = ShareInboxNotifierProvider._();

final class ShareInboxNotifierProvider
    extends $NotifierProvider<ShareInboxNotifier, ShareInboxState> {
  ShareInboxNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shareInboxProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shareInboxNotifierHash();

  @$internal
  @override
  ShareInboxNotifier create() => ShareInboxNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShareInboxState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShareInboxState>(value),
    );
  }
}

String _$shareInboxNotifierHash() =>
    r'a63338f4d95b3de1f3e39ef8f382b12c3ac308b0';

abstract class _$ShareInboxNotifier extends $Notifier<ShareInboxState> {
  ShareInboxState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ShareInboxState, ShareInboxState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShareInboxState, ShareInboxState>,
              ShareInboxState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
