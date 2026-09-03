import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/models/daily_schedule_mask.dart';
import 'package:parrot_trainer/ui/schedule_mask_editor.dart';

void main() {
  Future<_Harness> pumpEditor(
    WidgetTester tester,
    DailyScheduleMask initial,
  ) async {
    final harness = _Harness(initial);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 420, child: harness.build()),
          ),
        ),
      ),
    );
    return harness;
  }

  testWidgets('tap OFF cell turns it ON and saves once', (tester) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOff);
    await tester.tap(find.byKey(const Key('schedule-slot-0')));
    await tester.pump();
    expect(harness.callbacks, 1);
    expect(harness.mask.isEnabled(0), isTrue);
  });

  testWidgets('tap ON cell turns it OFF', (tester) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOn);
    await tester.tap(find.byKey(const Key('schedule-slot-0')));
    await tester.pump();
    expect(harness.callbacks, 1);
    expect(harness.mask.isEnabled(0), isFalse);
  });

  testWidgets('drag beginning on OFF paints every crossed cell ON', (
    tester,
  ) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOff);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('schedule-slot-0'))),
    );
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('schedule-slot-3'))),
    );
    expect(harness.callbacks, 0);
    await gesture.up();
    await tester.pump();
    expect(harness.callbacks, 1);
    for (var slot = 0; slot <= 3; slot++) {
      expect(harness.mask.isEnabled(slot), isTrue, reason: 'slot $slot');
    }
  });

  testWidgets('drag beginning on ON paints every crossed cell OFF', (
    tester,
  ) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOn);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('schedule-slot-4'))),
    );
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('schedule-slot-7'))),
    );
    await gesture.up();
    await tester.pump();
    for (var slot = 4; slot <= 7; slot++) {
      expect(harness.mask.isEnabled(slot), isFalse, reason: 'slot $slot');
    }
  });

  testWidgets('many moves inside one cell do not change stroke mode', (
    tester,
  ) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOff);
    final center = tester.getCenter(find.byKey(const Key('schedule-slot-0')));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(i.isEven ? 1 : -1, .2));
    }
    await gesture.up();
    await tester.pump();
    expect(harness.callbacks, 1);
    expect(harness.mask.isEnabled(0), isTrue);
  });

  testWidgets('returning to a visited cell does not toggle it again', (
    tester,
  ) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOff);
    final first = tester.getCenter(find.byKey(const Key('schedule-slot-0')));
    final second = tester.getCenter(find.byKey(const Key('schedule-slot-1')));
    final gesture = await tester.startGesture(first);
    await gesture.moveTo(second);
    await gesture.moveTo(first);
    await gesture.up();
    await tester.pump();
    expect(harness.mask.isEnabled(0), isTrue);
    expect(harness.mask.isEnabled(1), isTrue);
    expect(harness.callbacks, 1);
  });

  testWidgets('fast drag interpolates intermediate cells', (tester) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOff);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('schedule-slot-0'))),
    );
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('schedule-slot-3'))),
      timeStamp: const Duration(milliseconds: 10),
    );
    await gesture.up();
    await tester.pump();
    expect(harness.mask.isEnabled(1), isTrue);
    expect(harness.mask.isEnabled(2), isTrue);
    expect(harness.callbacks, 1);
  });

  testWidgets('cancel persists the edits once', (tester) async {
    final harness = await pumpEditor(tester, DailyScheduleMask.allOff);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('schedule-slot-0'))),
    );
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('schedule-slot-1'))),
    );
    await gesture.cancel();
    await tester.pump();
    expect(harness.callbacks, 1);
    expect(harness.mask.isEnabled(0), isTrue);
    expect(harness.mask.isEnabled(1), isTrue);
  });
}

class _Harness {
  _Harness(this.mask);

  DailyScheduleMask mask;
  int callbacks = 0;

  Widget build() => ScheduleMaskEditor(
    mask: mask,
    onChanged: (value) {
      callbacks++;
      mask = value;
    },
  );
}
