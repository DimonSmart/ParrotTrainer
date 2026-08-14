import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/tts_service.dart';

class VoicesScreen extends StatefulWidget {
  const VoicesScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<VoicesScreen> createState() => _VoicesScreenState();
}

class _VoicesScreenState extends State<VoicesScreen> {
  String _voiceFilter = '';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final settings = controller.settings;
      final filter = _voiceFilter.trim().toLowerCase();
      final voices = controller.voices.where((voice) {
        if (filter.isEmpty) return true;
        return voice.name.toLowerCase().contains(filter) ||
            voice.locale.toLowerCase().contains(filter);
      }).toList();
      return Scaffold(
        appBar: AppBar(title: const Text('Голоса и речь')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Настройки речи',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      key: const Key('previewSpeechSettings'),
                      onPressed: controller.previewSpeechSettings,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Проверить звучание'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            TextField(
              key: const Key('voiceFilter'),
              onChanged: (value) => setState(() => _voiceFilter = value),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                labelText: 'Фильтр голосов',
                hintText: 'Например, ru или Russian',
              ),
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
            else if (voices.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('По этому фильтру голоса не найдены.'),
                ),
              )
            else
              ...voices.map(
                (voice) => _VoiceTile(controller: controller, voice: voice),
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
