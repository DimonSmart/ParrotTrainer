class TrainingStatistics {
  const TrainingStatistics({
    this.totalPhrasesSpoken = 0,
    this.responsesToSound = 0,
    this.timeoutPhrases = 0,
    this.soundEvents = 0,
  });

  final int totalPhrasesSpoken;
  final int responsesToSound;
  final int timeoutPhrases;
  final int soundEvents;

  int get responsePercent => totalPhrasesSpoken == 0
      ? 0
      : (responsesToSound * 100 / totalPhrasesSpoken).round();

  TrainingStatistics copyWith({
    int? totalPhrasesSpoken,
    int? responsesToSound,
    int? timeoutPhrases,
    int? soundEvents,
  }) => TrainingStatistics(
    totalPhrasesSpoken: totalPhrasesSpoken ?? this.totalPhrasesSpoken,
    responsesToSound: responsesToSound ?? this.responsesToSound,
    timeoutPhrases: timeoutPhrases ?? this.timeoutPhrases,
    soundEvents: soundEvents ?? this.soundEvents,
  );

  Map<String, int> toJson() => {
    'totalPhrasesSpoken': totalPhrasesSpoken,
    'responsesToSound': responsesToSound,
    'timeoutPhrases': timeoutPhrases,
    'soundEvents': soundEvents,
  };

  factory TrainingStatistics.fromJson(Map<String, dynamic> json) =>
      TrainingStatistics(
        totalPhrasesSpoken: (json['totalPhrasesSpoken'] as num?)?.toInt() ?? 0,
        responsesToSound: (json['responsesToSound'] as num?)?.toInt() ?? 0,
        timeoutPhrases: (json['timeoutPhrases'] as num?)?.toInt() ?? 0,
        soundEvents: (json['soundEvents'] as num?)?.toInt() ?? 0,
      );
}
