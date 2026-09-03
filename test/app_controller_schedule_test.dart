import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/controllers/app_controller.dart';
import 'package:parrot_trainer/models/activity_history.dart';
import 'package:parrot_trainer/models/daily_schedule_mask.dart';
import 'package:parrot_trainer/models/training_settings.dart';
import 'package:parrot_trainer/models/training_statistics.dart';
import 'package:parrot_trainer/services/activity_history_repository.dart';
import 'package:parrot_trainer/services/audio_level_service.dart';
import 'package:parrot_trainer/services/keep_screen_on_service.dart';
import 'package:parrot_trainer/services/repositories.dart';
import 'package:parrot_trainer/services/tts_service.dart';

void main() {
  test('trainer remains enabled while schedule starts and stops sessions', () async {
    var now = DateTime(2026, 1, 1, 9);
    var mask = DailyScheduleMask.allOff;
    for (var slot = 32; slot < 34; slot++) {
      mask = mask.withSlot(slot, true);
    }
    for (var slot = 48; slot < 52; slot++) {
      mask = mask.withSlot(slot, true);
    }
    final settings = TrainingSettings.defaults.copyWith(
      dailyScheduleEnabled: true,
      dailySchedule: mask,
    );
    final controller = AppController(
      settingsRepository: _SettingsRepository(settings),
      statisticsRepository: _StatisticsRepository(),
      activityHistoryRepository: _ActivityRepository(),
      audio: _AudioService(),
      tts: _TtsService(),
      keepScreenOn: _KeepScreenOnService(),
      now: () => now,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final accepted = await controller.startTraining();
    expect(accepted, isTrue);
    expect(controller.trainingEnabled, isTrue);
    expect(controller.session.isRunning, isFalse);

    now = DateTime(2026, 1, 1, 8, 10);
    await controller.updateSettings(controller.settings);
    expect(controller.trainingEnabled, isTrue);
    expect(controller.session.isRunning, isTrue);

    now = DateTime(2026, 1, 1, 8, 30);
    await controller.updateSettings(controller.settings);
    expect(controller.trainingEnabled, isTrue);
    expect(controller.session.isRunning, isFalse);

    now = DateTime(2026, 1, 1, 12, 15);
    await controller.updateSettings(controller.settings);
    expect(controller.session.isRunning, isTrue);

    await controller.stopTraining();
    expect(controller.trainingEnabled, isFalse);
    expect(controller.session.isRunning, isFalse);

    now = DateTime(2026, 1, 1, 12, 30);
    await controller.updateSettings(controller.settings);
    expect(controller.session.isRunning, isFalse);
  });

  test('changing the current slot synchronizes once without disabling trainer', () async {
    final now = DateTime(2026, 1, 1, 10, 5);
    final repository = _SettingsRepository(
      TrainingSettings.defaults.copyWith(
        dailyScheduleEnabled: true,
        dailySchedule: DailyScheduleMask.allOn,
      ),
    );
    final controller = AppController(
      settingsRepository: repository,
      statisticsRepository: _StatisticsRepository(),
      activityHistoryRepository: _ActivityRepository(),
      audio: _AudioService(),
      tts: _TtsService(),
      keepScreenOn: _KeepScreenOnService(),
      now: () => now,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.startTraining();
    expect(controller.session.isRunning, isTrue);

    final currentSlot = DailyScheduleMask.slotFor(now);
    await controller.updateSettings(
      controller.settings.copyWith(
        dailySchedule: controller.settings.dailySchedule.withSlot(
          currentSlot,
          false,
        ),
      ),
    );
    expect(repository.saveCount, 1);
    expect(controller.trainingEnabled, isTrue);
    expect(controller.session.isRunning, isFalse);

    await controller.updateSettings(
      controller.settings.copyWith(
        dailySchedule: controller.settings.dailySchedule.withSlot(
          currentSlot,
          true,
        ),
      ),
    );
    expect(repository.saveCount, 2);
    expect(controller.session.isRunning, isTrue);
  });
}

class _SettingsRepository extends SettingsRepository {
  _SettingsRepository(this.value);
  TrainingSettings value;
  int saveCount = 0;

  @override
  Future<TrainingSettings> load() async => value;

  @override
  Future<void> save(TrainingSettings settings) async {
    saveCount++;
    value = settings;
  }

  @override
  Future<void> reset() async {}
}

class _StatisticsRepository extends StatisticsRepository {
  @override
  Future<TrainingStatistics> load() async => const TrainingStatistics();

  @override
  Future<void> save(TrainingStatistics statistics) async {}

  @override
  Future<void> reset() async {}
}

class _ActivityRepository extends ActivityHistoryRepository {
  final Map<String, DailyActivity> values = {};

  @override
  Future<DailyActivity?> loadDay(DateTime date) async =>
      values[DailyActivity(date: date).dateKey];

  @override
  Future<List<DailyActivity>> loadMonth(int year, int month) async => values.values
      .where((item) => item.date.year == year && item.date.month == month)
      .toList();

  @override
  Future<void> saveDay(DailyActivity day) async {
    values[day.dateKey] = day;
  }

  @override
  Future<void> reset() async => values.clear();
}

class _AudioService extends AudioLevelService {
  final StreamController<double> _controller = StreamController.broadcast();

  @override
  Stream<double> get levels => _controller.stream;

  @override
  Future<bool> start() async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _controller.close();
}

class _TtsService implements TtsService {
  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> speak(
    String phrase,
    TrainingSettings settings,
    TtsVoice? voice,
  ) async {}

  @override
  Future<void> stop() async {}
}

class _KeepScreenOnService implements KeepScreenOnService {
  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> setBackgroundTrainingEnabled(bool enabled) async {}
}
