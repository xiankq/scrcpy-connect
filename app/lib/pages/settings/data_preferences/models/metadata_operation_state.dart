final class MetadataOperationState {
  const MetadataOperationState({
    this.busy = false,
    this.refreshPending = false,
    this.message,
  });

  final bool busy;
  final bool refreshPending;
  final String? message;
}
