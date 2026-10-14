String formatCompactNumber(num value) {
  final number = value.toDouble();
  if (number.abs() < 1000) return number.round().toString();

  String format(num amount, String suffix) {
    final rounded = amount >= 100
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(1);
    return '${rounded.replaceFirst(RegExp(r'\.0$'), '').replaceAll('.', ',')}$suffix';
  }

  final absolute = number.abs();
  if (absolute >= 1000000) return format(number / 1000000, 'M');
  return format(number / 1000, 'K');
}
