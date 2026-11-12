// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'clipboard_focus_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 页面持有焦点租约；旧页面释放不能清除新页面或新作用域的焦点。

@ProviderFor(ClipboardFocusNotifier)
final clipboardFocusProvider = ClipboardFocusNotifierProvider._();

/// 页面持有焦点租约；旧页面释放不能清除新页面或新作用域的焦点。
final class ClipboardFocusNotifierProvider
    extends $NotifierProvider<ClipboardFocusNotifier, ClipboardFocus?> {
  /// 页面持有焦点租约；旧页面释放不能清除新页面或新作用域的焦点。
  ClipboardFocusNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clipboardFocusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clipboardFocusNotifierHash();

  @$internal
  @override
  ClipboardFocusNotifier create() => ClipboardFocusNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipboardFocus? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipboardFocus?>(value),
    );
  }
}

String _$clipboardFocusNotifierHash() =>
    r'35da131044fb1a8336011c19ef87728eff2f4d9e';

/// 页面持有焦点租约；旧页面释放不能清除新页面或新作用域的焦点。

abstract class _$ClipboardFocusNotifier extends $Notifier<ClipboardFocus?> {
  ClipboardFocus? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClipboardFocus?, ClipboardFocus?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClipboardFocus?, ClipboardFocus?>,
              ClipboardFocus?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
