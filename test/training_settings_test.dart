import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/models/daily_schedule_mask.dart';
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

  test('default mask is 09:00 inclusive through 21:00 exclusive', () {
    final settings = TrainingSettings.defaults.copyWith(
      dailyScheduleEnabled: true,
    );
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 1, 8, 59)), isFalse);
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 1, 9)), isTrue);
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 1, 20, 59)), isTrue);
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 1, 21)), isFalse);
  });

  test('disabled schedule ignores the persisted mask', () {
    final settings = TrainingSettings.defaults.copyWith(
      dailyScheduleEnabled: false,
      dailySchedule: DailyScheduleMask.allOff,
    );
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 1, 3)), isTrue);
  });

  test('legacy persisted range migrates and new JSON drops legacy keys', () {
    final settings = TrainingSettings.fromJson({
      'dailyScheduleEnabled': true,
      'scheduleStartMinute': 22 * 60 + 7,
      'scheduleEndMinute': 6 * 60 + 2,
    });
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 1, 22)), isTrue);
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 2, 6)), isTrue);
    expect(settings.isTrainingAllowedAt(DateTime(2026, 1, 2, 6, 15)), isFalse);

    final json = settings.toJson();
    expect(json['scheduleMask'], isA<List<int>>());
    expect(json.containsKey('scheduleStartMinute'), isFalse);
    expect(json.containsKey('scheduleEndMinute'), isFalse);
  });

  test('legacy equal boundaries migrate to unrestricted mask', () {
    final settings = TrainingSettings.fromJson({
      'dailyScheduleEnabled': true,
      'scheduleStartMinute': 600,
      'scheduleEndMinute': 600,
    });
    expect(settings.dailySchedule, DailyScheduleMask.allOn);
  });

  test('new schedule mask survives settings JSON round trip', () {
    final schedule = DailyScheduleMask.allOff
        .withSlot(1, true)
        .withSlot(30, true)
        .withSlot(95, true);
    final settings = TrainingSettings.defaults.copyWith(
      dailyScheduleEnabled: true,
      dailySchedule: schedule,
    );
    expect(TrainingSettings.fromJson(settings.toJson()).dailySchedule, schedule);
  });
}
