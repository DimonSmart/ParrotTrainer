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

  test('scheduled hours include start and exclude end', () {
    final settings = TrainingSettings.defaults.copyWith(
      dailyScheduleEnabled: true,
      scheduleStartMinute: 9 * 60,
      scheduleEndMinute: 21 * 60,
    );
    expect(settings.isWithinScheduledHours(DateTime(2026, 1, 1, 9)), isTrue);
    expect(
      settings.isWithinScheduledHours(DateTime(2026, 1, 1, 20, 59)),
      isTrue,
    );
    expect(settings.isWithinScheduledHours(DateTime(2026, 1, 1, 21)), isFalse);
  });

  test('scheduled hours support an interval that crosses midnight', () {
    final settings = TrainingSettings.defaults.copyWith(
      dailyScheduleEnabled: true,
      scheduleStartMinute: 22 * 60,
      scheduleEndMinute: 6 * 60,
    );
    expect(settings.isWithinScheduledHours(DateTime(2026, 1, 1, 23)), isTrue);
    expect(
      settings.isWithinScheduledHours(DateTime(2026, 1, 2, 5, 59)),
      isTrue,
    );
    expect(settings.isWithinScheduledHours(DateTime(2026, 1, 2, 6)), isFalse);
  });
}
