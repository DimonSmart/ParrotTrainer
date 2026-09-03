import 'daily_time_grid.dart';

class ActivityBucket {
  const ActivityBucket({
    this.activeSeconds = 0,
    this.soundEvents = 0,
    this.phrasesSpoken = 0,
    this.responsesToSound = 0,
    this.timeoutPhrases = 0,
    this.birdReplyOpportunities = 0,
    this.birdRepliesAfterApp = 0,
  });

  final int activeSeconds,
      soundEvents,
      phrasesSpoken,
      responsesToSound,
      timeoutPhrases,
      birdReplyOpportunities,
      birdRepliesAfterApp;

  bool get hasData =>
      activeSeconds > 0 ||
      soundEvents > 0 ||
      phrasesSpoken > 0 ||
      responsesToSound > 0 ||
      timeoutPhrases > 0 ||
      birdReplyOpportunities > 0 ||
      birdRepliesAfterApp > 0;

  ActivityBucket add(ActivityBucket value) => ActivityBucket(
    activeSeconds: activeSeconds + value.activeSeconds,
    soundEvents: soundEvents + value.soundEvents,
    phrasesSpoken: phrasesSpoken + value.phrasesSpoken,
    responsesToSound: responsesToSound + value.responsesToSound,
    timeoutPhrases: timeoutPhrases + value.timeoutPhrases,
    birdReplyOpportunities:
        birdReplyOpportunities + value.birdReplyOpportunities,
    birdRepliesAfterApp: birdRepliesAfterApp + value.birdRepliesAfterApp,
  );

  Map<String, Object> toJson() => {
    'activeSeconds': activeSeconds,
    'soundEvents': soundEvents,
    'phrasesSpoken': phrasesSpoken,
    'responsesToSound': responsesToSound,
    'timeoutPhrases': timeoutPhrases,
    'birdReplyOpportunities': birdReplyOpportunities,
    'birdRepliesAfterApp': birdRepliesAfterApp,
  };

  factory ActivityBucket.fromJson(Map<String, dynamic> json) => ActivityBucket(
    activeSeconds: _nonNegative(json['activeSeconds']),
    soundEvents: _nonNegative(json['soundEvents']),
    phrasesSpoken: _nonNegative(json['phrasesSpoken']),
    responsesToSound: _nonNegative(json['responsesToSound']),
    timeoutPhrases: _nonNegative(json['timeoutPhrases']),
    birdReplyOpportunities: _nonNegative(json['birdReplyOpportunities']),
    birdRepliesAfterApp: _nonNegative(json['birdRepliesAfterApp']),
  );
}

int _nonNegative(Object? value) =>
    (value as num?)?.toInt().clamp(0, 1 << 31) ?? 0;

class DailyActivity {
  DailyActivity({required DateTime date, Map<int, ActivityBucket>? buckets})
    : date = DateTime(date.year, date.month, date.day),
      buckets = Map.unmodifiable(buckets ?? const {});

  final DateTime date;
  final Map<int, ActivityBucket> buckets;

  static int bucketIndex(DateTime value) => DailyTimeGrid.slotIndex(value);
  static DateTime bucketStart(DateTime day, int index) =>
      DailyTimeGrid.slotStart(day, index);
  String get dateKey =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  ActivityBucket get total =>
      buckets.values.fold(const ActivityBucket(), (sum, item) => sum.add(item));
  int get trainingSeconds => total.activeSeconds;
  int get soundEvents => total.soundEvents;
  int get phrasesSpoken => total.phrasesSpoken;
  int get responsesToSound => total.responsesToSound;
  int get timeoutPhrases => total.timeoutPhrases;
  int get birdReplyOpportunities => total.birdReplyOpportunities;
  int get birdRepliesAfterApp => total.birdRepliesAfterApp;
  int? get responsePercent => phrasesSpoken == 0
      ? null
      : (responsesToSound * 100 / phrasesSpoken).round();
  int? get birdReplyPercent => birdReplyOpportunities == 0
      ? null
      : (birdRepliesAfterApp * 100 / birdReplyOpportunities).round();
  bool get hasData => buckets.isNotEmpty;

  DailyActivity addToBucket(int index, ActivityBucket value) {
    if (index < 0 || index >= DailyTimeGrid.slotCount || !value.hasData) {
      return this;
    }
    final copy = Map<int, ActivityBucket>.from(buckets);
    copy[index] = (copy[index] ?? const ActivityBucket()).add(value);
    return DailyActivity(date: date, buckets: copy);
  }

  Map<String, Object> toJson() => {
    'date': dateKey,
    'buckets': {
      for (final entry in buckets.entries)
        entry.key.toString(): entry.value.toJson(),
    },
  };

  factory DailyActivity.fromJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.tryParse(json['date'] as String? ?? '');
    if (parsedDate == null) {
      throw const FormatException('Invalid activity date');
    }
    final rawBuckets = json['buckets'] as Map? ?? const {};
    final buckets = <int, ActivityBucket>{};
    rawBuckets.forEach((key, value) {
      final index = int.tryParse(key.toString());
      if (index != null &&
          index >= 0 &&
          index < DailyTimeGrid.slotCount &&
          value is Map) {
        final bucket = ActivityBucket.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (bucket.hasData) buckets[index] = bucket;
      }
    });
    return DailyActivity(date: parsedDate, buckets: buckets);
  }
}
