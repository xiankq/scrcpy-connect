/// Result returned by the native independent-window host boundary.
final class IndependentWindowReceipt {
  const IndependentWindowReceipt._({
    required this.opened,
    this.windowId,
    this.reason,
  });

  const IndependentWindowReceipt.opened(String id)
    : this._(opened: true, windowId: id);

  const IndependentWindowReceipt.fallback(String message)
    : this._(opened: false, reason: message);

  final bool opened;
  final String? windowId;
  final String? reason;
}
