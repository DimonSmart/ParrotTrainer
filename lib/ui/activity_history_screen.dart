import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/activity_history.dart';
import '../l10n/app_strings.dart';

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  late DateTime _selected;
  late DateTime _month;
  Map<String, DailyActivity> _days = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
    widget.controller.addListener(_onControllerChanged);
    _loadMonth();
  }

  void _onControllerChanged() {
    final today = DateTime.now();
    if (_month.year == today.year && _month.month == today.month) _loadMonth();
  }

  Future<void> _loadMonth() async {
    final month = _month;
    final values = await widget.controller.loadActivityMonth(
      month.year,
      month.month,
    );
    if (!mounted || month != _month) return;
    setState(() {
      _days = {for (final day in values) day.dateKey: day};
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _loading = true;
    });
    _loadMonth();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = _days[_key(_selected)];
    final hasAnyHistory = _days.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.activity), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            _Calendar(
              month: _month,
              selected: _selected,
              days: _days,
              onPrevious: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
              onSelect: (value) => setState(() => _selected = value),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (!hasAnyHistory && _isCurrentMonth(_month))
              _MessageCard(context.strings.noHistory)
            else if (day == null)
              _MessageCard(context.strings.noDayData)
            else ...[
              _Summary(day: day),
              const SizedBox(height: 14),
              _Heatmap(day: day),
            ],
          ],
        ),
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.selected,
    required this.days,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });
  final DateTime month, selected;
  final Map<String, DailyActivity> days;
  final VoidCallback onPrevious, onNext;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final values = List<DateTime?>.generate(
      leading + count,
      (index) => index < leading
          ? null
          : DateTime(month.year, month.month, index - leading + 1),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: context.strings.previousMonth,
                ),
                Expanded(
                  child: Text(
                    _monthName(context, month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF207B25),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: context.strings.nextMonth,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final label in context.strings.weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ((values.length + 6) ~/ 7) * 7,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                final value = index < values.length ? values[index] : null;
                if (value == null) return const SizedBox.shrink();
                final activity = days[_key(value)];
                final selectedDay = _sameDay(value, selected);
                final sounds = activity?.soundEvents ?? 0;
                final active = activity?.trainingSeconds ?? 0;
                final intensity = sounds == 0
                    ? 0.0
                    : (sounds / 8).clamp(.2, 1.0);
                final color = sounds > 0
                    ? Color.lerp(
                        const Color(0xFFDDF0D4),
                        const Color(0xFF268A32),
                        intensity,
                      )!
                    : Colors.transparent;
                return Semantics(
                  button: true,
                  selected: selectedDay,
                  label:
                      '${value.day} ${sounds > 0
                          ? context.strings.sounds(sounds)
                          : active > 0
                          ? context.strings.trainingWithoutSounds
                          : context.strings.noDataShort}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(value),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedDay
                              ? const Color(0xFF126D26)
                              : active > 0
                              ? const Color(0xFF9BCB9B)
                              : Colors.transparent,
                          width: selectedDay ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${value.day}',
                          style: TextStyle(
                            fontWeight: selectedDay
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: sounds > 4 ? Colors.white : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.day});
  final DailyActivity day;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.statisticsFor(_dateLabel(day.date)),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF207B25),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _row(
            context.strings.activity,
            context.strings.sounds(day.soundEvents),
          ),
          _row(context.strings.phrasesSpoken, '${day.phrasesSpoken}'),
          _row(
            context.strings.responsesToChirps,
            '${day.responsesToSound} (${_percent(day.responsePercent)})',
          ),
          _row(
            context.strings.parrotReplied,
            '${day.birdRepliesAfterApp} / ${day.birdReplyOpportunities} (${_percent(day.birdReplyPercent)})',
          ),
          _row(
            context.strings.trainingTime,
            context.strings.duration(day.trainingSeconds),
          ),
        ],
      ),
    ),
  );
  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.day});
  final DailyActivity day;
  @override
  Widget build(BuildContext context) {
    final active = day.buckets.entries
        .where((entry) => entry.value.activeSeconds > 0)
        .map((entry) => entry.key ~/ 4)
        .toList();
    final first = active.isEmpty ? 0 : active.reduce((a, b) => a < b ? a : b);
    final last = active.isEmpty ? 2 : active.reduce((a, b) => a > b ? a : b);
    final from = (first - 1).clamp(0, 23), to = (last + 1).clamp(0, 23);
    final maximum = day.buckets.values.fold(
      0,
      (max, bucket) => bucket.soundEvents > max ? bucket.soundEvents : max,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.activityByTime,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF207B25),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Row(
                children: [
                  for (final label in ['00', '15', '30', '45'])
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (var hour = from; hour <= to; hour++)
              _HeatmapRow(hour: hour, day: day, maximum: maximum),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _Legend(
                  color: const Color(0xFFE0E0E0),
                  text: context.strings.activityOff,
                ),
                _Legend(
                  color: const Color(0xFFFFFFFF),
                  outlined: true,
                  text: context.strings.activityRunningQuiet,
                ),
                _Legend(
                  color: const Color(0xFF51A85A),
                  text: context.strings.activityLegend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatmapRow extends StatelessWidget {
  const _HeatmapRow({
    required this.hour,
    required this.day,
    required this.maximum,
  });
  final int hour, maximum;
  final DailyActivity day;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            '${hour.toString().padLeft(2, '0')}:00',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        for (var quarter = 0; quarter < 4; quarter++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _HeatCell(
                bucket: day.buckets[hour * 4 + quarter],
                maximum: maximum,
              ),
            ),
          ),
      ],
    ),
  );
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.bucket, required this.maximum});
  final ActivityBucket? bucket;
  final int maximum;
  @override
  Widget build(BuildContext context) {
    final sounds = bucket?.soundEvents ?? 0;
    final active = bucket?.activeSeconds ?? 0;
    final color = sounds > 0
        ? Color.lerp(
            const Color(0xFFDDF0D4),
            const Color(0xFF238331),
            sounds / maximum,
          )!
        : active > 0
        ? Colors.white
        : const Color(0xFFE0E0E0);
    return Semantics(
      label: sounds > 0
          ? context.strings.sounds(sounds)
          : active > 0
          ? context.strings.trainingRunningNoSounds
          : context.strings.trainingStopped,
      child: Container(
        height: 33,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active > 0 && sounds == 0
                ? const Color(0xFF9E9E9E)
                : Colors.transparent,
          ),
        ),
        child: sounds > 0
            ? Text(
                '$sounds',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: sounds / maximum > .55 ? Colors.white : Colors.black87,
                ),
              )
            : null,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.text,
    this.outlined = false,
  });
  final Color color;
  final String text;
  final bool outlined;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: outlined ? Colors.grey : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

String _key(DateTime value) => DailyActivity(date: value).dateKey;
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
bool _isCurrentMonth(DateTime value) {
  final now = DateTime.now();
  return value.year == now.year && value.month == now.month;
}

String _percent(int? value) => value == null ? '—' : '$value%';
String _dateLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
String _monthName(BuildContext context, DateTime value) {
  final name = context.strings.months[value.month - 1];
  return '$name ${value.year}';
}
