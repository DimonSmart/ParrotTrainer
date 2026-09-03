class DailyTimeGrid {
  const DailyTimeGrid._();

  static const int slotMinutes = 15;
  static const int slotsPerHour = 4;
  static const int slotCount = 24 * slotsPerHour;

  static int slotIndex(DateTime value) =>
      value.hour * slotsPerHour + value.minute ~/ slotMinutes;

  static DateTime slotStart(DateTime day, int index) {
    RangeError.checkValidIndex(index, List.filled(slotCount, null), 'index');
    return DateTime(
      day.year,
      day.month,
      day.day,
      index ~/ slotsPerHour,
      (index % slotsPerHour) * slotMinutes,
    );
  }

  static DateTime nextBoundary(DateTime value) {
    final minute = (value.minute ~/ slotMinutes + 1) * slotMinutes;
    return DateTime(value.year, value.month, value.day, value.hour, minute);
  }
}
