class TrainingSettings {
  const TrainingSettings({
    required this.phrases,
    required this.soundThresholdDb,
    required this.minimumInterval,
    required this.maximumInterval,
    required this.silenceAfterSound,
    required this.selectedVoiceIds,
    required this.speechRate,
    required this.speechPitch,
    required this.speechVolume,
  });

  static const defaults = TrainingSettings(
    phrases: ['Привет', 'Привет, моя птичка', 'Арчик, говорящий попугайчик'],
    soundThresholdDb: -42,
    minimumInterval: Duration(seconds: 5),
    maximumInterval: Duration(seconds: 30),
    silenceAfterSound: Duration(seconds: 2),
    selectedVoiceIds: [],
    speechRate: 0.45,
    speechPitch: 1,
    speechVolume: 1,
  );

  final List<String> phrases;
  final double soundThresholdDb;
  final Duration minimumInterval;
  final Duration maximumInterval;
  final Duration silenceAfterSound;
  final List<String> selectedVoiceIds;
  final double speechRate;
  final double speechPitch;
  final double speechVolume;

  TrainingSettings copyWith({
    List<String>? phrases,
    double? soundThresholdDb,
    Duration? minimumInterval,
    Duration? maximumInterval,
    Duration? silenceAfterSound,
    List<String>? selectedVoiceIds,
    double? speechRate,
    double? speechPitch,
    double? speechVolume,
  }) => TrainingSettings(
    phrases: phrases ?? this.phrases,
    soundThresholdDb: soundThresholdDb ?? this.soundThresholdDb,
    minimumInterval: minimumInterval ?? this.minimumInterval,
    maximumInterval: maximumInterval ?? this.maximumInterval,
    silenceAfterSound: silenceAfterSound ?? this.silenceAfterSound,
    selectedVoiceIds: selectedVoiceIds ?? this.selectedVoiceIds,
    speechRate: speechRate ?? this.speechRate,
    speechPitch: speechPitch ?? this.speechPitch,
    speechVolume: speechVolume ?? this.speechVolume,
  );

  Map<String, Object> toJson() => {
    'phrases': phrases,
    'soundThresholdDb': soundThresholdDb,
    'minimumIntervalMs': minimumInterval.inMilliseconds,
    'maximumIntervalMs': maximumInterval.inMilliseconds,
    'silenceAfterSoundMs': silenceAfterSound.inMilliseconds,
    'selectedVoiceIds': selectedVoiceIds,
    'speechRate': speechRate,
    'speechPitch': speechPitch,
    'speechVolume': speechVolume,
  };

  factory TrainingSettings.fromJson(Map<String, dynamic> json) {
    final defaults = TrainingSettings.defaults;
    return TrainingSettings(
      phrases: (json['phrases'] as List?)?.cast<String>() ?? defaults.phrases,
      soundThresholdDb:
          (json['soundThresholdDb'] as num?)?.toDouble() ??
          defaults.soundThresholdDb,
      minimumInterval: Duration(
        milliseconds:
            (json['minimumIntervalMs'] as num?)?.toInt() ??
            defaults.minimumInterval.inMilliseconds,
      ),
      maximumInterval: Duration(
        milliseconds:
            (json['maximumIntervalMs'] as num?)?.toInt() ??
            defaults.maximumInterval.inMilliseconds,
      ),
      silenceAfterSound: Duration(
        milliseconds:
            (json['silenceAfterSoundMs'] as num?)?.toInt() ??
            defaults.silenceAfterSound.inMilliseconds,
      ),
      selectedVoiceIds:
          (json['selectedVoiceIds'] as List?)?.cast<String>() ??
          defaults.selectedVoiceIds,
      speechRate:
          (json['speechRate'] as num?)?.toDouble() ?? defaults.speechRate,
      speechPitch:
          (json['speechPitch'] as num?)?.toDouble() ?? defaults.speechPitch,
      speechVolume:
          (json['speechVolume'] as num?)?.toDouble() ?? defaults.speechVolume,
    );
  }
}
