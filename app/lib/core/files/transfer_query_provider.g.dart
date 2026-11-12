// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'transfer_query_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(transferHistory)
final transferHistoryProvider = TransferHistoryProvider._();

final class TransferHistoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<FileTransferCollection>,
          FileTransferCollection,
          FutureOr<FileTransferCollection>
        >
    with
        $FutureModifier<FileTransferCollection>,
        $FutureProvider<FileTransferCollection> {
  TransferHistoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'transferHistoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transferHistoryHash();

  @$internal
  @override
  $FutureProviderElement<FileTransferCollection> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<FileTransferCollection> create(Ref ref) {
    return transferHistory(ref);
  }
}

String _$transferHistoryHash() => r'6e886ced04a65fa197c46ca42b450186dabcd203';

@ProviderFor(transferDetails)
final transferDetailsProvider = TransferDetailsFamily._();

final class TransferDetailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<FileTransferSnapshot>,
          FileTransferSnapshot,
          FutureOr<FileTransferSnapshot>
        >
    with
        $FutureModifier<FileTransferSnapshot>,
        $FutureProvider<FileTransferSnapshot> {
  TransferDetailsProvider._({
    required TransferDetailsFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'transferDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$transferDetailsHash();

  @override
  String toString() {
    return r'transferDetailsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<FileTransferSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<FileTransferSnapshot> create(Ref ref) {
    final argument = this.argument as String;
    return transferDetails(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TransferDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$transferDetailsHash() => r'9f34160c683fc196e637be68885ca8ec2bcc591e';

final class TransferDetailsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<FileTransferSnapshot>, String> {
  TransferDetailsFamily._()
    : super(
        retry: _noRetry,
        name: r'transferDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TransferDetailsProvider call(String id) =>
      TransferDetailsProvider._(argument: id, from: this);

  @override
  String toString() => r'transferDetailsProvider';
}
