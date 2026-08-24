import 'dart:ui';

import 'package:flutter_tts/flutter_tts.dart';

import '../l10n/app_language.dart';
import '../models/training_settings.dart';

class TtsVoice {
  const TtsVoice({required this.name, required this.locale});
  final String name;
  final String locale;
  String get id => '$name|$locale';
  Map<String, String> get platformValue => {'name': name, 'locale': locale};
}

abstract interface class TtsService {
  Future<List<TtsVoice>> getVoices();
  Future<void> speak(String phrase, TrainingSettings settings, TtsVoice? voice);
  Future<void> stop();
}

class AndroidTtsService implements TtsService {
  AndroidTtsService() {
    _ready = _tts.awaitSpeakCompletion(true).then((_) {});
  }
  final FlutterTts _tts = FlutterTts();
  late final Future<void> _ready;

  AppLanguage get _language =>
      AppLanguage.resolve(PlatformDispatcher.instance.locale.languageCode);

  @override
  Future<List<TtsVoice>> getVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return [];
    final voices = raw
        .whereType<Map>()
        .map(
          (item) => TtsVoice(
            name: item['name']?.toString() ?? '',
            locale: item['locale']?.toString() ?? '',
          ),
        )
        .where((voice) => voice.name.isNotEmpty)
        .toList();
    final languageCode = _language.code;
    voices.sort((a, b) {
      final aPreferred = a.locale.toLowerCase().startsWith(languageCode) ? 0 : 1;
      final bPreferred = b.locale.toLowerCase().startsWith(languageCode) ? 0 : 1;
      return aPreferred != bPreferred
          ? aPreferred.compareTo(bPreferred)
          : a.name.compareTo(b.name);
    });
    return voices;
  }

  @override
  Future<void> speak(
    String phrase,
    TrainingSettings settings,
    TtsVoice? voice,
  ) async {
    await _ready;
    await _tts.setLanguage(
      switch (_language) {
        AppLanguage.english => 'en-US',
        AppLanguage.russian => 'ru-RU',
        AppLanguage.spanish => 'es-ES',
      },
    );
    if (voice != null) await _tts.setVoice(voice.platformValue);
    await _tts.setSpeechRate(settings.speechRate);
    await _tts.setPitch(settings.speechPitch);
    await _tts.setVolume(settings.speechVolume);
    await _tts.speak(phrase);
  }

  @override
  Future<void> stop() async => _tts.stop();
}
