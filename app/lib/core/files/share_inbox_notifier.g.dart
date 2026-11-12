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
    r'3f2ea7f0caba72d22849d118c3cdc6dc456d9267';

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
