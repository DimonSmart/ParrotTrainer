import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/daily_schedule_mask.dart';

class ScheduleMaskEditor extends StatefulWidget {
  const ScheduleMaskEditor({
    super.key,
    required this.mask,
    required this.onChanged,
  });

  final DailyScheduleMask mask;
  final ValueChanged<DailyScheduleMask> onChanged;

  @override
  State<ScheduleMaskEditor> createState() => _ScheduleMaskEditorState();
}

class _ScheduleMaskEditorState extends State<ScheduleMaskEditor> {
  static const double _rowHeight = 28;

  late DailyScheduleMask _draft = widget.mask;
  final Set<int> _visited = {};
  bool? _paintState;
  bool _changed = false;
  Offset? _downPosition;
  Offset? _previousPosition;
  double _cellWidth = 1;

  @override
  void didUpdateWidget(covariant ScheduleMaskEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_paintState == null && oldWidget.mask != widget.mask) {
      _draft = widget.mask;
    }
  }

  int? _slotAt(Offset position) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= _cellWidth * 4 ||
        position.dy >= _rowHeight * 24) {
      return null;
    }
    final hour = position.dy ~/ _rowHeight;
    final quarter = position.dx ~/ _cellWidth;
    final slot = hour * 4 + quarter;
    return slot >= 0 && slot < DailyScheduleMask.slotCount ? slot : null;
  }

  bool _applyPosition(Offset position) {
    final slot = _slotAt(position);
    final state = _paintState;
    if (slot == null || state == null || !_visited.add(slot)) return false;
    final updated = _draft.withSlot(slot, state);
    if (updated == _draft) return false;
    _draft = updated;
    _changed = true;
    return true;
  }

  void _beginStroke(Offset position) {
    final slot = _slotAt(position);
    if (slot == null) return;
    _visited.clear();
    _paintState = !_draft.isEnabled(slot);
    _previousPosition = position;
    if (_applyPosition(position)) setState(() {});
  }

  void _continueStroke(Offset position) {
    final previous = _previousPosition;
    if (_paintState == null || previous == null) return;
    final distance = (position - previous).distance;
    final sampleSize = math.max(1.0, math.min(_cellWidth, _rowHeight) * .4);
    final steps = math.max(1, (distance / sampleSize).ceil());
    var changed = false;
    for (var step = 1; step <= steps; step++) {
      final sample = Offset.lerp(previous, position, step / steps)!;
      changed = _applyPosition(sample) || changed;
    }
    _previousPosition = position;
    if (changed) setState(() {});
  }

  void _finishStroke() {
    if (_paintState == null) return;
    final shouldNotify = _changed;
    final result = _draft;
    _visited.clear();
    _paintState = null;
    _previousPosition = null;
    _downPosition = null;
    _changed = false;
    if (shouldNotify) widget.onChanged(result);
  }

  void _tap(Offset position) {
    _beginStroke(position);
    _finishStroke();
  }

  @override
  Widget build(BuildContext context) {
    final onColor = Theme.of(context).colorScheme.primaryContainer;
    final onBorder = Theme.of(context).colorScheme.primary;
    final offColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final offBorder = Theme.of(context).dividerColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 54, child: Text('Time')),
            Expanded(
              child: Row(
                children: const ['00', '15', '30', '45']
                    .map(
                      (label) => Expanded(
                        child: Text(label, textAlign: TextAlign.center),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 54,
              child: Column(
                children: List.generate(
                  24,
                  (hour) => SizedBox(
                    height: _rowHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${hour.toString().padLeft(2, '0')}:00'),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _cellWidth = constraints.maxWidth / 4;
                  return GestureDetector(
                    key: const Key('schedule-grid-gesture-area'),
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (details) => _downPosition = details.localPosition,
                    onPanStart: (details) => _beginStroke(
                      _downPosition ?? details.localPosition,
                    ),
                    onPanUpdate: (details) =>
                        _continueStroke(details.localPosition),
                    onPanEnd: (_) => _finishStroke(),
                    onPanCancel: _finishStroke,
                    onTapUp: (details) => _tap(details.localPosition),
                    onTapCancel: () => _downPosition = null,
                    child: Column(
                      children: List.generate(
                        24,
                        (hour) => SizedBox(
                          height: _rowHeight,
                          child: Row(
                            children: List.generate(4, (quarter) {
                              final slot = hour * 4 + quarter;
                              final enabled = _draft.isEnabled(slot);
                              return Expanded(
                                child: AnimatedContainer(
                                  key: Key('schedule-slot-$slot'),
                                  duration: const Duration(milliseconds: 70),
                                  margin: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(
                                    color: enabled ? onColor : offColor,
                                    border: Border.all(
                                      color: enabled ? onBorder : offBorder,
                                      width: enabled ? 1.6 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
