// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'clipboard_sync_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(clipboardSync)
final clipboardSyncProvider = ClipboardSyncProvider._();

final class ClipboardSyncProvider
    extends $FunctionalProvider<ClipboardSync, ClipboardSync, ClipboardSync>
    with $Provider<ClipboardSync> {
  ClipboardSyncProvider._()
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
  String debugGetCreateSourceHash() => _$clipboardSyncHash();

  @$internal
  @override
  $ProviderElement<ClipboardSync> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ClipboardSync create(Ref ref) {
    return clipboardSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipboardSync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipboardSync>(value),
    );
  }
}

String _$clipboardSyncHash() => r'5e694468252011dfab0d6abdd1ecc20c0893e5a1';
