import 'dart:math';

class TrainingPhrase {
  const TrainingPhrase({
    required this.id,
    required this.text,
    this.recordedAudioPath,
  }) : assert(id != ''),
       assert(text != '');

  final String id;
  final String text;
  final String? recordedAudioPath;

  TrainingPhrase copyWith({
    String? text,
    String? recordedAudioPath,
    bool clearRecording = false,
  }) => TrainingPhrase(
    id: id,
    text: text ?? this.text,
    recordedAudioPath: clearRecording
        ? null
        : recordedAudioPath ?? this.recordedAudioPath,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'recordedAudioPath': recordedAudioPath,
  };

  factory TrainingPhrase.fromJson(Map<String, dynamic> json) => TrainingPhrase(
    id: json['id'] as String? ?? newId(),
    text: (json['text'] as String? ?? '').trim(),
    recordedAudioPath: json['recordedAudioPath'] as String?,
  );

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  @override
  bool operator ==(Object other) =>
      other is TrainingPhrase &&
      other.id == id &&
      other.text == text &&
      other.recordedAudioPath == recordedAudioPath;
  @override
  int get hashCode => Object.hash(id, text, recordedAudioPath);
}
