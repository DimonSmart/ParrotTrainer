import 'daily_time_grid.dart';

class DailyScheduleMask {
  const DailyScheduleMask.words(this.word0, this.word1, this.word2)
    : assert(word0 >= 0 && word0 <= _wordMask),
      assert(word1 >= 0 && word1 <= _wordMask),
      assert(word2 >= 0 && word2 <= _wordMask);

  static const int slotCount = DailyTimeGrid.slotCount;
  static const int _wordMask = 0xffffffff;

  static const DailyScheduleMask allOff = DailyScheduleMask.words(0, 0, 0);
  static const DailyScheduleMask allOn = DailyScheduleMask.words(
    _wordMask,
    _wordMask,
    _wordMask,
  );

  final int word0;
  final int word1;
  final int word2;

  factory DailyScheduleMask.fromJson(Object? value) {
    if (value is! List || value.length != 3) {
      throw const FormatException('scheduleMask must contain three words');
    }
    final words = value.map((item) {
      if (item is! num) {
        throw const FormatException('scheduleMask words must be numbers');
      }
      final word = item.toInt();
      if (word < 0 || word > _wordMask) {
        throw const FormatException('scheduleMask word is outside 32-bit range');
      }
      return word;
    }).toList(growable: false);
    return DailyScheduleMask.words(words[0], words[1], words[2]);
  }

  factory DailyScheduleMask.fromLegacyRange(int startMinute, int endMinute) {
    final start = startMinute.clamp(0, 1439);
    final end = endMinute.clamp(0, 1439);
    if (start == end) return allOn;

    final startSlot = start ~/ DailyTimeGrid.slotMinutes;
    final endBoundary = (end + DailyTimeGrid.slotMinutes - 1) ~/
        DailyTimeGrid.slotMinutes;
    var result = allOff;

    if (start < end) {
      for (var slot = startSlot; slot < endBoundary; slot++) {
        result = result.withSlot(slot, true);
      }
      return result;
    }

    for (var slot = startSlot; slot < slotCount; slot++) {
      result = result.withSlot(slot, true);
    }
    for (var slot = 0; slot < endBoundary; slot++) {
      result = result.withSlot(slot, true);
    }
    return result;
  }

  List<int> toJson() => [word0, word1, word2];

  bool isEnabled(int slot) {
    RangeError.checkValidIndex(slot, List.filled(slotCount, null), 'slot');
    final word = switch (slot ~/ 32) {
      0 => word0,
      1 => word1,
      _ => word2,
    };
    return (word & (1 << (slot % 32))) != 0;
  }

  DailyScheduleMask withSlot(int slot, bool enabled) {
    RangeError.checkValidIndex(slot, List.filled(slotCount, null), 'slot');
    final bit = 1 << (slot % 32);
    int update(int value) =>
        enabled ? (value | bit) & _wordMask : value & ~bit & _wordMask;
    return switch (slot ~/ 32) {
      0 => DailyScheduleMask.words(update(word0), word1, word2),
      1 => DailyScheduleMask.words(word0, update(word1), word2),
      _ => DailyScheduleMask.words(word0, word1, update(word2)),
    };
  }

  static int slotFor(DateTime time) => DailyTimeGrid.slotIndex(time);

  bool isTrainingAllowedAt(DateTime time) => isEnabled(slotFor(time));

  DateTime? nextTransitionAfter(DateTime time) {
    final currentState = isTrainingAllowedAt(time);
    var boundary = DailyTimeGrid.nextBoundary(time);
    var slot = (slotFor(time) + 1) % slotCount;
    for (var checked = 0; checked < slotCount; checked++) {
      if (isEnabled(slot) != currentState) return boundary;
      boundary = boundary.add(const Duration(minutes: DailyTimeGrid.slotMinutes));
      slot = (slot + 1) % slotCount;
    }
    return null;
  }

  bool get isUniform => this == allOff || this == allOn;

  @override
  bool operator ==(Object other) =>
      other is DailyScheduleMask &&
      other.word0 == word0 &&
      other.word1 == word1 &&
      other.word2 == word2;

  @override
  int get hashCode => Object.hash(word0, word1, word2);
}
