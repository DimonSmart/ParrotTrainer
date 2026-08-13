import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/training_settings.dart';
import '../models/training_statistics.dart';

class SettingsRepository {
  static const _key = 'training_settings_v1';

  Future<TrainingSettings> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    if (value == null) return TrainingSettings.defaults;
    try {
      return TrainingSettings.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    } catch (_) {
      return TrainingSettings.defaults;
    }
  }

  Future<void> save(TrainingSettings settings) async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(settings.toJson()),
      );

  Future<void> reset() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

class StatisticsRepository {
  static const _key = 'training_statistics_v1';

  Future<TrainingStatistics> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    if (value == null) return const TrainingStatistics();
    try {
      return TrainingStatistics.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    } catch (_) {
      return const TrainingStatistics();
    }
  }

  Future<void> save(TrainingStatistics statistics) async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(statistics.toJson()),
      );

  Future<void> reset() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
