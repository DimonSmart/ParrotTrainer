import 'dart:ui';

import 'package:flutter_tts/flutter_tts.dart';

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
    voices.sort((a, b) {
      final aRu = a.locale.toLowerCase().startsWith('ru') ? 0 : 1;
      final bRu = b.locale.toLowerCase().startsWith('ru') ? 0 : 1;
      return aRu != bRu ? aRu.compareTo(bRu) : a.name.compareTo(b.name);
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
      PlatformDispatcher.instance.locale.languageCode == 'en'
          ? 'en-US'
          : 'ru-RU',
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
