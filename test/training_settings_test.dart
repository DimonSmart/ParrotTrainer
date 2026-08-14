import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/models/training_phrase.dart';
import 'package:parrot_trainer/models/training_settings.dart';

void main() {
  test('legacy phrases and maximum interval migrate', () {
    final settings = TrainingSettings.fromJson({
      'phrases': ['Привет', ''],
      'maximumIntervalMs': 30000,
    });
    expect(settings.phrases.single.text, 'Привет');
    expect(settings.idlePromptMaxInterval, const Duration(seconds: 30));
  });

  test('phrase recording survives settings round trip', () {
    final settings = TrainingSettings.defaults.copyWith(
      phrases: const [
        TrainingPhrase(
          id: 'one',
          text: 'Привет',
          recordedAudioPath: '/audio.m4a',
        ),
      ],
    );
    final restored = TrainingSettings.fromJson(settings.toJson());
    expect(restored.phrases.single, settings.phrases.single);
  });

  test('invalid idle interval is normalized', () {
    final settings = TrainingSettings.fromJson({
      'idlePromptMinIntervalMs': 60000,
      'idlePromptMaxIntervalMs': 30000,
    });
    expect(settings.idlePromptMinInterval, settings.idlePromptMaxInterval);
  });
}
