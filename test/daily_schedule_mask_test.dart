import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/models/daily_schedule_mask.dart';

void main() {
  group('DailyScheduleMask', () {
    test('uses exactly 96 quarter-hour slots', () {
      expect(DailyScheduleMask.slotCount, 96);
      expect(DailyScheduleMask.slotFor(DateTime(2026, 1, 1)), 0);
      expect(DailyScheduleMask.slotFor(DateTime(2026, 1, 1, 0, 14, 59)), 0);
      expect(DailyScheduleMask.slotFor(DateTime(2026, 1, 1, 0, 15)), 1);
      expect(DailyScheduleMask.slotFor(DateTime(2026, 1, 1, 0, 30)), 2);
      expect(DailyScheduleMask.slotFor(DateTime(2026, 1, 1, 0, 45)), 3);
      expect(DailyScheduleMask.slotFor(DateTime(2026, 1, 1, 23, 45)), 95);
    });

    test('independently enables non-adjacent slots', () {
      final mask = DailyScheduleMask.allOff
          .withSlot(3, true)
          .withSlot(17, true)
          .withSlot(95, true);
      expect(mask.isEnabled(3), isTrue);
      expect(mask.isEnabled(17), isTrue);
      expect(mask.isEnabled(95), isTrue);
      expect(mask.isEnabled(4), isFalse);
      expect(mask.isEnabled(94), isFalse);
    });

    test('all off and all on are valid', () {
      for (var slot = 0; slot < DailyScheduleMask.slotCount; slot++) {
        expect(DailyScheduleMask.allOff.isEnabled(slot), isFalse);
        expect(DailyScheduleMask.allOn.isEnabled(slot), isTrue);
      }
    });

    test('midnight needs no special lookup semantics', () {
      final mask = DailyScheduleMask.allOff
          .withSlot(95, true)
          .withSlot(0, true);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 1, 23, 50)), isTrue);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 2, 0, 5)), isTrue);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 2, 0, 15)), isFalse);
    });

    test('finds next transition inside a day', () {
      var mask = DailyScheduleMask.allOff;
      for (var slot = 32; slot < 34; slot++) {
        mask = mask.withSlot(slot, true);
      }
      for (var slot = 48; slot < 52; slot++) {
        mask = mask.withSlot(slot, true);
      }
      expect(
        mask.nextTransitionAfter(DateTime(2026, 1, 1, 8, 10)),
        DateTime(2026, 1, 1, 8, 30),
      );
      expect(
        mask.nextTransitionAfter(DateTime(2026, 1, 1, 9)),
        DateTime(2026, 1, 1, 12),
      );
    });

    test('finds next transition across midnight', () {
      var mask = DailyScheduleMask.allOff;
      for (var slot = 28; slot < 32; slot++) {
        mask = mask.withSlot(slot, true);
      }
      expect(
        mask.nextTransitionAfter(DateTime(2026, 1, 1, 23, 50)),
        DateTime(2026, 1, 2, 7),
      );
    });

    test('uniform masks have no transition', () {
      expect(
        DailyScheduleMask.allOff.nextTransitionAfter(DateTime(2026, 1, 1, 12)),
        isNull,
      );
      expect(
        DailyScheduleMask.allOn.nextTransitionAfter(DateTime(2026, 1, 1, 12)),
        isNull,
      );
    });

    test('JSON round trip preserves all three 32-bit words', () {
      final mask = const DailyScheduleMask.words(
        0x80000001,
        0xf0f0f0f0,
        0xffffffff,
      );
      expect(DailyScheduleMask.fromJson(mask.toJson()), mask);
    });
  });

  group('legacy schedule migration', () {
    test('normal range rounds outward', () {
      final mask = DailyScheduleMask.fromLegacyRange(9 * 60 + 7, 10 * 60 + 8);
      expect(mask.isEnabled(36), isTrue);
      expect(mask.isEnabled(40), isTrue);
      expect(mask.isEnabled(41), isFalse);
      expect(mask.isEnabled(35), isFalse);
    });

    test('range crossing midnight becomes two parts', () {
      final mask = DailyScheduleMask.fromLegacyRange(22 * 60 + 5, 6 * 60 + 2);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 1, 22)), isTrue);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 1, 23, 45)), isTrue);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 2, 0)), isTrue);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 2, 6)), isTrue);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 2, 6, 15)), isFalse);
      expect(mask.isTrainingAllowedAt(DateTime(2026, 1, 2, 21, 45)), isFalse);
    });

    test('equal legacy boundaries migrate to all on', () {
      expect(DailyScheduleMask.fromLegacyRange(600, 600), DailyScheduleMask.allOn);
    });
  });
}
