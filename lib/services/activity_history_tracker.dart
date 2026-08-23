import '../models/activity_history.dart';
import '../models/training_statistics.dart';
import 'activity_history_repository.dart';

class ActivityHistoryTracker {
  ActivityHistoryTracker(this._repository, {this.onChanged});
  final ActivityHistoryRepository _repository;
  final void Function()? onChanged;
  Future<void> _operations = Future.value();
  DateTime? _activeSince;

  void start(DateTime now) => _activeSince ??= now;
  Future<void> checkpoint(DateTime now) => _addActiveTime(now);
  Future<void> stop(DateTime now) async {
    await _addActiveTime(now);
    _activeSince = null;
  }

  Future<void> recordDelta(
    TrainingStatistics before,
    TrainingStatistics after,
    DateTime now,
  ) {
    final delta = statisticsDelta(before, after);
    if (!delta.hasData) return Future.value();
    return _update(now, DailyActivity.bucketIndex(now), delta);
  }

  static ActivityBucket statisticsDelta(
    TrainingStatistics before,
    TrainingStatistics after,
  ) => ActivityBucket(
    soundEvents: _delta(after.soundEvents, before.soundEvents),
    phrasesSpoken: _delta(after.totalPhrasesSpoken, before.totalPhrasesSpoken),
    responsesToSound: _delta(after.responsesToSound, before.responsesToSound),
    timeoutPhrases: _delta(after.timeoutPhrases, before.timeoutPhrases),
    birdReplyOpportunities: _delta(
      after.birdReplyOpportunities,
      before.birdReplyOpportunities,
    ),
    birdRepliesAfterApp: _delta(
      after.birdRepliesAfterApp,
      before.birdRepliesAfterApp,
    ),
  );

  static int _delta(int after, int before) =>
      after > before ? after - before : 0;

  static List<ActivityTimeSlice> splitActiveTime(DateTime start, DateTime end) {
    if (!end.isAfter(start)) return const [];
    final result = <ActivityTimeSlice>[];
    var cursor = start;
    while (cursor.isBefore(end)) {
      final boundary = DailyActivity.bucketStart(
        cursor,
        DailyActivity.bucketIndex(cursor),
      ).add(const Duration(minutes: 15));
      final sliceEnd = boundary.isBefore(end) ? boundary : end;
      final seconds = sliceEnd.difference(cursor).inSeconds;
      if (seconds > 0) {
        result.add(ActivityTimeSlice(cursor, seconds));
      }
      cursor = sliceEnd;
    }
    return result;
  }

  Future<void> _addActiveTime(DateTime now) async {
    final start = _activeSince;
    if (start == null || !now.isAfter(start)) {
      _activeSince = now;
      return;
    }
    _activeSince = now;
    for (final slice in splitActiveTime(start, now)) {
      await _update(
        slice.start,
        DailyActivity.bucketIndex(slice.start),
        ActivityBucket(activeSeconds: slice.seconds),
      );
    }
  }

  Future<void> _update(DateTime date, int bucket, ActivityBucket value) {
    _operations = _operations.then((_) async {
      final day = await _repository.loadDay(date) ?? DailyActivity(date: date);
      await _repository.saveDay(day.addToBucket(bucket, value));
      onChanged?.call();
    });
    return _operations;
  }
}

class ActivityTimeSlice {
  const ActivityTimeSlice(this.start, this.seconds);
  final DateTime start;
  final int seconds;
}
