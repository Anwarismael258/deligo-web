class MozambiqueTime {
  MozambiqueTime._();

  static const Duration utcOffset = Duration(hours: 2);

  static DateTime now() => DateTime.now().toUtc().add(utcOffset);

  static DateTime from(DateTime value) => value.toUtc().add(utcOffset);

  static DateTime? tryParse(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : from(parsed);
  }
}
