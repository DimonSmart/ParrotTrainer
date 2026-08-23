import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity_history.dart';

class ActivityHistoryRepository {
  static const _daysKey = 'activity_history_days_v1';
  static const _prefix = 'activity_history_v1_';

  Future<DailyActivity?> loadDay(DateTime date) async {
    final day = DailyActivity(date: date);
    final value = (await SharedPreferences.getInstance()).getString(
      '$_prefix${day.dateKey}',
    );
    if (value == null) return null;
    try {
      return DailyActivity.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<List<DailyActivity>> loadMonth(int year, int month) async {
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getStringList(_daysKey) ?? const [];
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';
    final result = <DailyActivity>[];
    for (final key in keys.where((value) => value.startsWith(prefix))) {
      final value = preferences.getString('$_prefix$key');
      if (value == null) continue;
      try {
        result.add(
          DailyActivity.fromJson(jsonDecode(value) as Map<String, dynamic>),
        );
      } catch (_) {}
    }
    return result;
  }

  Future<void> saveDay(DailyActivity day) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_prefix${day.dateKey}',
      jsonEncode(day.toJson()),
    );
    final days = (preferences.getStringList(_daysKey) ?? const []).toSet()
      ..add(day.dateKey);
    await preferences.setStringList(_daysKey, days.toList()..sort());
  }

  Future<void> reset() async {
    final preferences = await SharedPreferences.getInstance();
    final days = preferences.getStringList(_daysKey) ?? const [];
    for (final day in days) {
      await preferences.remove('$_prefix$day');
    }
    await preferences.remove(_daysKey);
  }
}
