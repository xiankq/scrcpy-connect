// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'clipboard_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(clipboardCoordinator)
final clipboardCoordinatorProvider = ClipboardCoordinatorProvider._();

final class ClipboardCoordinatorProvider
    extends
        $FunctionalProvider<
          ClipboardCoordinator,
          ClipboardCoordinator,
          ClipboardCoordinator
        >
    with $Provider<ClipboardCoordinator> {
  ClipboardCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clipboardCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clipboardCoordinatorHash();

  @$internal
  @override
  $ProviderElement<ClipboardCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ClipboardCoordinator create(Ref ref) {
    return clipboardCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipboardCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipboardCoordinator>(value),
    );
  }
}

String _$clipboardCoordinatorHash() =>
    r'69de8a85bc3a415059a41be94566c21acd7123cf';
