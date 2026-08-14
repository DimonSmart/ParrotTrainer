import 'training_phrase.dart';

class TrainingSettings {
  TrainingSettings({
    required List<TrainingPhrase> phrases,
    required this.soundThresholdDb,
    required this.minimumInterval,
    required Duration idlePromptMinInterval,
    required Duration idlePromptMaxInterval,
    required this.silenceAfterSound,
    required this.selectedVoiceIds,
    required this.speechRate,
    required this.speechPitch,
    required this.speechVolume,
    this.focusPhraseId,
    this.primaryVoiceId,
    this.maxConsecutiveIdlePrompts = 2,
  }) : phrases = phrases.isEmpty
           ? defaults.phrases
           : List.unmodifiable(phrases),
       idlePromptMinInterval = idlePromptMinInterval < minimumInterval
           ? minimumInterval
           : idlePromptMinInterval,
       idlePromptMaxInterval =
           idlePromptMaxInterval <
               (idlePromptMinInterval < minimumInterval
                   ? minimumInterval
                   : idlePromptMinInterval)
           ? (idlePromptMinInterval < minimumInterval
                 ? minimumInterval
                 : idlePromptMinInterval)
           : idlePromptMaxInterval;

  static final defaults = TrainingSettings(
    phrases: const [
      TrainingPhrase(id: 'default-hello', text: 'Привет'),
      TrainingPhrase(id: 'default-bird', text: 'Привет, моя птичка'),
      TrainingPhrase(id: 'default-parrot', text: 'Арчик, говорящий попугайчик'),
    ],
    soundThresholdDb: -42,
    minimumInterval: const Duration(seconds: 5),
    idlePromptMinInterval: const Duration(seconds: 60),
    idlePromptMaxInterval: const Duration(seconds: 180),
    silenceAfterSound: const Duration(seconds: 2),
    selectedVoiceIds: const [],
    speechRate: .45,
    speechPitch: 1,
    speechVolume: 1,
  );

  final List<TrainingPhrase> phrases;
  final double soundThresholdDb;
  final Duration minimumInterval,
      idlePromptMinInterval,
      idlePromptMaxInterval,
      silenceAfterSound;
  final List<String> selectedVoiceIds;
  final double speechRate, speechPitch, speechVolume;
  final String? focusPhraseId, primaryVoiceId;
  final int maxConsecutiveIdlePrompts;
  Duration get maximumInterval => idlePromptMaxInterval;
  TrainingSettings copyWith({
    List<TrainingPhrase>? phrases,
    double? soundThresholdDb,
    Duration? minimumInterval,
    Duration? idlePromptMinInterval,
    Duration? idlePromptMaxInterval,
    Duration? silenceAfterSound,
    List<String>? selectedVoiceIds,
    double? speechRate,
    double? speechPitch,
    double? speechVolume,
    String? focusPhraseId,
    bool clearFocusPhrase = false,
    String? primaryVoiceId,
    int? maxConsecutiveIdlePrompts,
  }) => TrainingSettings(
    phrases: phrases ?? this.phrases,
    soundThresholdDb: soundThresholdDb ?? this.soundThresholdDb,
    minimumInterval: minimumInterval ?? this.minimumInterval,
    idlePromptMinInterval: idlePromptMinInterval ?? this.idlePromptMinInterval,
    idlePromptMaxInterval: idlePromptMaxInterval ?? this.idlePromptMaxInterval,
    silenceAfterSound: silenceAfterSound ?? this.silenceAfterSound,
    selectedVoiceIds: selectedVoiceIds ?? this.selectedVoiceIds,
    speechRate: speechRate ?? this.speechRate,
    speechPitch: speechPitch ?? this.speechPitch,
    speechVolume: speechVolume ?? this.speechVolume,
    focusPhraseId: clearFocusPhrase
        ? null
        : focusPhraseId ?? this.focusPhraseId,
    primaryVoiceId: primaryVoiceId ?? this.primaryVoiceId,
    maxConsecutiveIdlePrompts:
        maxConsecutiveIdlePrompts ?? this.maxConsecutiveIdlePrompts,
  );
  Map<String, Object?> toJson() => {
    'phrases': phrases.map((p) => p.toJson()).toList(),
    'soundThresholdDb': soundThresholdDb,
    'minimumIntervalMs': minimumInterval.inMilliseconds,
    'idlePromptMinIntervalMs': idlePromptMinInterval.inMilliseconds,
    'idlePromptMaxIntervalMs': idlePromptMaxInterval.inMilliseconds,
    'silenceAfterSoundMs': silenceAfterSound.inMilliseconds,
    'selectedVoiceIds': selectedVoiceIds,
    'speechRate': speechRate,
    'speechPitch': speechPitch,
    'speechVolume': speechVolume,
    'focusPhraseId': focusPhraseId,
    'primaryVoiceId': primaryVoiceId,
    'maxConsecutiveIdlePrompts': maxConsecutiveIdlePrompts,
  };
  factory TrainingSettings.fromJson(Map<String, dynamic> json) {
    final d = defaults;
    final raw = json['phrases'] as List?;
    final phrases = raw == null
        ? d.phrases
        : raw
              .where((item) => item is! String || item.trim().isNotEmpty)
              .map(
                (item) => item is String
                    ? TrainingPhrase(id: _legacyId(item), text: item.trim())
                    : TrainingPhrase.fromJson(
                        Map<String, dynamic>.from(item as Map),
                      ),
              )
              .where((p) => p.text.isNotEmpty)
              .toList();
    Duration duration(String key, Duration fallback) => Duration(
      milliseconds: (json[key] as num?)?.toInt() ?? fallback.inMilliseconds,
    );
    final min = duration('idlePromptMinIntervalMs', d.idlePromptMinInterval);
    final max = duration(
      'idlePromptMaxIntervalMs',
      json.containsKey('maximumIntervalMs')
          ? duration('maximumIntervalMs', d.idlePromptMaxInterval)
          : d.idlePromptMaxInterval,
    );
    return TrainingSettings(
      phrases: phrases.isEmpty ? d.phrases : phrases,
      soundThresholdDb:
          (json['soundThresholdDb'] as num?)?.toDouble() ?? d.soundThresholdDb,
      minimumInterval: duration('minimumIntervalMs', d.minimumInterval),
      idlePromptMinInterval: min <= max ? min : max,
      idlePromptMaxInterval: max,
      silenceAfterSound: duration('silenceAfterSoundMs', d.silenceAfterSound),
      selectedVoiceIds:
          (json['selectedVoiceIds'] as List?)?.cast<String>() ??
          d.selectedVoiceIds,
      speechRate: (json['speechRate'] as num?)?.toDouble() ?? d.speechRate,
      speechPitch: (json['speechPitch'] as num?)?.toDouble() ?? d.speechPitch,
      speechVolume:
          (json['speechVolume'] as num?)?.toDouble() ?? d.speechVolume,
      focusPhraseId: json['focusPhraseId'] as String?,
      primaryVoiceId: json['primaryVoiceId'] as String?,
      maxConsecutiveIdlePrompts:
          ((json['maxConsecutiveIdlePrompts'] as num?)?.toInt() ??
                  d.maxConsecutiveIdlePrompts)
              .clamp(1, 100),
    );
  }
  static String _legacyId(String text) => 'legacy-${text.hashCode.abs()}';
}
