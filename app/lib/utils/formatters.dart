String bytes(dynamic input) {
  final n = num.tryParse('$input') ?? 0;
  if (n < 1024) return '${n.toInt()} B';
  if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1073741824) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1073741824).toStringAsFixed(1)} GB';
}
