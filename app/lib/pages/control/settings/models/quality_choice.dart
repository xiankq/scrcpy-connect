class QualityChoice<T> {
  const QualityChoice({
    required this.value,
    required this.label,
    required this.available,
    this.reason = '',
  });
  final T value;
  final String label;
  final bool available;
  final String reason;
}
