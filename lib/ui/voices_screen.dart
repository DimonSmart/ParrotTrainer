import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/tts_service.dart';

class VoicesScreen extends StatelessWidget {
  const VoicesScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final settings = controller.settings;
      return Scaffold(
        appBar: AppBar(title: const Text('Голоса и речь')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Установленные голоса',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Можно выбрать несколько. Если ничего не выбрано, используется голос Android по умолчанию.',
            ),
            const SizedBox(height: 12),
            if (controller.voices.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Android не сообщил об установленных TTS-голосах. Проверьте настройки синтеза речи.',
                  ),
                ),
              )
            else
              ...controller.voices.map(
                (voice) => _VoiceTile(controller: controller, voice: voice),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _SettingSlider(
                      label: 'Скорость речи',
                      value: settings.speechRate,
                      min: 0.2,
                      max: 0.8,
                      onChanged: (v) => controller.updateSettings(
                        settings.copyWith(speechRate: v),
                      ),
                    ),
                    _SettingSlider(
                      label: 'Высота голоса',
                      value: settings.speechPitch,
                      min: 0.5,
                      max: 2,
                      onChanged: (v) => controller.updateSettings(
                        settings.copyWith(speechPitch: v),
                      ),
                    ),
                    _SettingSlider(
                      label: 'Громкость',
                      value: settings.speechVolume,
                      min: 0,
                      max: 1,
                      onChanged: (v) => controller.updateSettings(
                        settings.copyWith(speechVolume: v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({required this.controller, required this.voice});
  final AppController controller;
  final TtsVoice voice;

  @override
  Widget build(BuildContext context) {
    final selected = controller.settings.selectedVoiceIds.contains(voice.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: selected,
        title: Text(voice.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(voice.locale),
        secondary: IconButton(
          icon: const Icon(Icons.play_circle_outline),
          tooltip: 'Прослушать',
          onPressed: () => controller.previewVoice(voice),
        ),
        onChanged: (value) {
          final ids = [...controller.settings.selectedVoiceIds];
          value == true ? ids.add(voice.id) : ids.remove(voice.id);
          controller.updateSettings(
            controller.settings.copyWith(
              selectedVoiceIds: ids.toSet().toList(),
            ),
          );
        },
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    ],
  );
}
