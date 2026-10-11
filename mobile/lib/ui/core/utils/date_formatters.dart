/// French date and time display. Everything is shown in the device's local
/// time; the values are instants parsed from the backend, never strings.
abstract final class DateFormatFr {
  static const _months = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  static const _weekdays = [
    'lun.',
    'mar.',
    'mer.',
    'jeu.',
    'ven.',
    'sam.',
    'dim.',
  ];

  /// `16:30`.
  static String time(DateTime value) {
    final local = value.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// `4 oct. 2026`.
  static String date(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  /// `4 oct. 2026 à 14:48`.
  static String dateTime(DateTime value) => '${date(value)} à ${time(value)}';

  /// A pickup time that is quick to scan: `Aujourd’hui · 16:30`,
  /// `Demain · 09:00`, otherwise `sam. 10 oct. · 16:30`. [now] is injectable
  /// for tests.
  static String pickup(DateTime value, {DateTime? now}) =>
      '${day(value, now: now)} · ${time(value)}';

  /// The day of [value] relative to today: `Aujourd’hui`, `Demain`, or
  /// `sam. 10 oct.`.
  static String day(DateTime value, {DateTime? now}) {
    final local = value.toLocal();
    final today = (now ?? DateTime.now()).toLocal();
    final dayDifference = DateTime(
      local.year,
      local.month,
      local.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    return switch (dayDifference) {
      0 => 'Aujourd’hui',
      1 => 'Demain',
      _ =>
        '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}',
    };
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
