import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/controllers/app_controller.dart';
import 'package:parrot_trainer/models/training_settings.dart';
import 'package:parrot_trainer/services/audio_level_service.dart';
import 'package:parrot_trainer/services/keep_screen_on_service.dart';
import 'package:parrot_trainer/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enabled trainer waits for schedule without turning off', () async {
    final now = DateTime.now();
    final currentMinute = now.hour * 60 + now.minute;
    final startMinute = (currentMinute + 10) % (24 * 60);
    final endMinute = (currentMinute + 20) % (24 * 60);
    final scheduledSettings = TrainingSettings.defaultsFor('en').copyWith(
      dailyScheduleEnabled: true,
      scheduleStartMinute: startMinute,
      scheduleEndMinute: endMinute,
      allowScreenToSleep: true,
    );
    SharedPreferences.setMockInitialValues({
      'training_settings_v1': jsonEncode(scheduledSettings.toJson()),
    });

    final audio = _FakeAudioLevelService();
    final keepScreenOn = _FakeKeepScreenOnService();
    final controller = AppController(
      audio: audio,
      tts: _FakeTtsService(),
      keepScreenOn: keepScreenOn,
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    expect(controller.settings.isWithinScheduledHours(DateTime.now()), isFalse);

    expect(await controller.startTraining(), isTrue);
    expect(controller.trainingEnabled, isTrue);
    expect(controller.session.isRunning, isFalse);
    expect(keepScreenOn.backgroundTrainingEnabled, isTrue);

    await controller.updateSettings(
      controller.settings.copyWith(dailyScheduleEnabled: false),
    );
    expect(controller.trainingEnabled, isTrue);
    expect(controller.session.isRunning, isTrue);

    await controller.updateSettings(scheduledSettings);
    expect(controller.trainingEnabled, isTrue);
    expect(controller.session.isRunning, isFalse);
    expect(keepScreenOn.backgroundTrainingEnabled, isTrue);

    await controller.stopTraining();
    expect(controller.trainingEnabled, isFalse);
    expect(controller.session.isRunning, isFalse);
    expect(keepScreenOn.backgroundTrainingEnabled, isFalse);
  });
}

class _FakeAudioLevelService extends AudioLevelService {
  final _controller = StreamController<double>.broadcast();

  @override
  Stream<double> get levels => _controller.stream;

  @override
  Future<bool> start() async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeKeepScreenOnService implements KeepScreenOnService {
  bool backgroundTrainingEnabled = false;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> setBackgroundTrainingEnabled(bool enabled) async {
    backgroundTrainingEnabled = enabled;
  }
}

class _FakeTtsService implements TtsService {
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
