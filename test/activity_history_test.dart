import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/models/activity_history.dart';
import 'package:parrot_trainer/models/training_statistics.dart';
import 'package:parrot_trainer/services/activity_history_tracker.dart';

void main() {
  test('uses 15-minute bucket indexes', () {
    expect(DailyActivity.bucketIndex(DateTime(2026, 8, 16, 10)), 40);
    expect(DailyActivity.bucketIndex(DateTime(2026, 8, 16, 10, 45)), 43);
  });

  test('aggregates buckets and omits undefined percentages', () {
    final day = DailyActivity(date: DateTime(2026, 8, 16))
        .addToBucket(
          40,
          const ActivityBucket(phrasesSpoken: 4, responsesToSound: 3),
        )
        .addToBucket(
          41,
          const ActivityBucket(
            birdReplyOpportunities: 2,
            birdRepliesAfterApp: 1,
          ),
        );
    expect(day.responsePercent, 75);
    expect(day.birdReplyPercent, 50);
    expect(DailyActivity(date: DateTime(2026)).responsePercent, isNull);
  });

  test('serializes sparse buckets and tolerates missing fields', () {
    final day = DailyActivity(
      date: DateTime(2026, 8, 16),
    ).addToBucket(40, const ActivityBucket(soundEvents: 2));
    final restored = DailyActivity.fromJson(day.toJson());
    expect(restored.buckets.keys, [40]);
    final sparse = DailyActivity.fromJson({
      'date': '2026-08-16',
      'buckets': {
        '41': {'soundEvents': 1},
      },
    });
    expect(sparse.buckets[41]!.activeSeconds, 0);
  });

  test('splits active time at bucket and midnight boundaries', () {
    final pieces = ActivityHistoryTracker.splitActiveTime(
      DateTime(2026, 8, 16, 10, 7),
      DateTime(2026, 8, 16, 10, 22),
    );
    expect(pieces.map((item) => item.seconds), [8 * 60, 7 * 60]);
    final midnight = ActivityHistoryTracker.splitActiveTime(
      DateTime(2026, 8, 16, 23, 55),
      DateTime(2026, 8, 17, 0, 5),
    );
    expect(midnight.map((item) => item.seconds), [5 * 60, 5 * 60]);
    expect(midnight.map((item) => item.start.day), [16, 17]);
  });

  test('statistics deltas never write negative values', () {
    final delta = ActivityHistoryTracker.statisticsDelta(
      const TrainingStatistics(soundEvents: 100),
      const TrainingStatistics(
        soundEvents: 0,
        totalPhrasesSpoken: 1,
        responsesToSound: 1,
      ),
    );
    expect(delta.soundEvents, 0);
    expect(delta.phrasesSpoken, 1);
    expect(delta.responsesToSound, 1);
  });
}
