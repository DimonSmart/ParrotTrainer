class TrainingStatistics {
  const TrainingStatistics({
    this.totalPhrasesSpoken = 0,
    this.responsesToSound = 0,
    this.timeoutPhrases = 0,
    this.soundEvents = 0,
    this.birdReplyOpportunities = 0,
    this.birdRepliesAfterApp = 0,
    this.successfulAttemptsByPhrase = const {},
  });
  final int totalPhrasesSpoken,
      responsesToSound,
      timeoutPhrases,
      soundEvents,
      birdReplyOpportunities,
      birdRepliesAfterApp;
  final Map<String, int> successfulAttemptsByPhrase;
  int get responsePercent => totalPhrasesSpoken == 0
      ? 0
      : (responsesToSound * 100 / totalPhrasesSpoken).round();
  int get birdReplyPercent => birdReplyOpportunities == 0
      ? 0
      : (birdRepliesAfterApp * 100 / birdReplyOpportunities).round();
  int get successfulAttemptsTotal =>
      successfulAttemptsByPhrase.values.fold(0, (sum, value) => sum + value);
  TrainingStatistics copyWith({
    int? totalPhrasesSpoken,
    int? responsesToSound,
    int? timeoutPhrases,
    int? soundEvents,
    int? birdReplyOpportunities,
    int? birdRepliesAfterApp,
    Map<String, int>? successfulAttemptsByPhrase,
  }) => TrainingStatistics(
    totalPhrasesSpoken: totalPhrasesSpoken ?? this.totalPhrasesSpoken,
    responsesToSound: responsesToSound ?? this.responsesToSound,
    timeoutPhrases: timeoutPhrases ?? this.timeoutPhrases,
    soundEvents: soundEvents ?? this.soundEvents,
    birdReplyOpportunities:
        birdReplyOpportunities ?? this.birdReplyOpportunities,
    birdRepliesAfterApp: birdRepliesAfterApp ?? this.birdRepliesAfterApp,
    successfulAttemptsByPhrase:
        successfulAttemptsByPhrase ?? this.successfulAttemptsByPhrase,
  );
  Map<String, Object> toJson() => {
    'totalPhrasesSpoken': totalPhrasesSpoken,
    'responsesToSound': responsesToSound,
    'timeoutPhrases': timeoutPhrases,
    'soundEvents': soundEvents,
    'birdReplyOpportunities': birdReplyOpportunities,
    'birdRepliesAfterApp': birdRepliesAfterApp,
    'successfulAttemptsByPhrase': successfulAttemptsByPhrase,
  };
  factory TrainingStatistics.fromJson(Map<String, dynamic> json) =>
      TrainingStatistics(
        totalPhrasesSpoken: (json['totalPhrasesSpoken'] as num?)?.toInt() ?? 0,
        responsesToSound: (json['responsesToSound'] as num?)?.toInt() ?? 0,
        timeoutPhrases: (json['timeoutPhrases'] as num?)?.toInt() ?? 0,
        soundEvents: (json['soundEvents'] as num?)?.toInt() ?? 0,
        birdReplyOpportunities:
            (json['birdReplyOpportunities'] as num?)?.toInt() ?? 0,
        birdRepliesAfterApp:
            (json['birdRepliesAfterApp'] as num?)?.toInt() ?? 0,
        successfulAttemptsByPhrase:
            (json['successfulAttemptsByPhrase'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), (value as num).toInt()),
            ) ??
            const {},
      );
}
