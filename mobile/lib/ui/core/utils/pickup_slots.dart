/// The pickup times a customer can choose: every 30 minutes (on the hour and
/// the half hour), from at least 30 minutes ahead to at most 48 hours ahead.
/// These are the same bounds the backend enforces; the backend stays the
/// authority (a slot can go stale while the screen is open).
abstract final class PickupSlots {
  static const minimumLead = Duration(minutes: 30);
  static const maximumLead = Duration(hours: 48);
  static const step = Duration(minutes: 30);

  /// Time for the request to reach the backend: a slot exactly 30 minutes
  /// away would already be too soon on arrival.
  static const _margin = Duration(minutes: 1);

  /// The slots available at [now], in local time, earliest first.
  static List<DateTime> generate(DateTime now) {
    final local = now.toLocal();
    final earliest = _ceil(local.add(minimumLead + _margin));
    final latest = local.add(maximumLead - _margin);
    final slots = <DateTime>[];
    for (
      var slot = earliest;
      !slot.isAfter(latest);
      slot = _addMinutes(slot, step.inMinutes)
    ) {
      slots.add(slot);
    }
    return slots;
  }

  /// Whether [slot] is still at least the minimum lead from [now].
  static bool isStillBookable(DateTime slot, DateTime now) =>
      !slot.isBefore(now.add(minimumLead + _margin));

  static DateTime _ceil(DateTime value) {
    final floored = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute < 30 ? 0 : 30,
    );
    return floored.isBefore(value) ? _addMinutes(floored, 30) : floored;
  }

  /// Calendar arithmetic, so a clock change never shifts a slot off :00/:30.
  static DateTime _addMinutes(DateTime value, int minutes) => DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute + minutes,
  );
}
