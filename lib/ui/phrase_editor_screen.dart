import 'package:flutter/material.dart';

import '../models/training_phrase.dart';
import '../services/phrase_recorder.dart';
import '../services/recorded_phrase_player.dart';

class PhraseEditorScreen extends StatefulWidget {
  const PhraseEditorScreen({super.key, required this.phrases});
  final List<TrainingPhrase> phrases;

  @override
  State<PhraseEditorScreen> createState() => _PhraseEditorScreenState();
}

class _PhraseEditorScreenState extends State<PhraseEditorScreen> {
  final _recorder = PhraseRecorder();
  final _player = LocalRecordedPhrasePlayer();
  late final List<TrainingPhrase> _phrases = List.of(widget.phrases);
  String? _recordingId;

  Future<void> _toggleRecording(TrainingPhrase phrase) async {
    if (_recordingId == phrase.id) {
      final path = await _recorder.stop();
      _replace(phrase.copyWith(recordedAudioPath: path));
      setState(() => _recordingId = null);
      return;
    }
    await _recorder.start(phrase.id);
    setState(() => _recordingId = phrase.id);
  }

  void _replace(TrainingPhrase phrase) {
    final index = _phrases.indexWhere((item) => item.id == phrase.id);
    if (index >= 0) setState(() => _phrases[index] = phrase);
  }

  Future<void> _delete(TrainingPhrase phrase) async {
    await _recorder.delete(phrase.recordedAudioPath);
    setState(() => _phrases.removeWhere((item) => item.id == phrase.id));
  }

  void _save() {
    final valid = _phrases
        .where((phrase) => phrase.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одну фразу')),
      );
      return;
    }
    Navigator.pop(context, valid);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Фразы для обучения'),
      actions: [
        IconButton(
          onPressed: _save,
          icon: const Icon(Icons.check),
          tooltip: 'Сохранить',
        ),
      ],
    ),
    body: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _phrases.length,
      itemBuilder: (context, index) {
        final phrase = _phrases[index];
        final recording = _recordingId == phrase.id;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextFormField(
                  initialValue: phrase.text,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: 'Фраза'),
                  onChanged: (text) => _replace(phrase.copyWith(text: text)),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _toggleRecording(phrase),
                      icon: Icon(recording ? Icons.stop : Icons.mic),
                      label: Text(recording ? 'Остановить' : 'Записать'),
                    ),
                    TextButton.icon(
                      onPressed: phrase.recordedAudioPath == null
                          ? null
                          : () => _player.playIfAvailable(
                              phrase.recordedAudioPath,
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Прослушать'),
                    ),
                    TextButton.icon(
                      onPressed: phrase.recordedAudioPath == null
                          ? null
                          : () async {
                              await _recorder.delete(phrase.recordedAudioPath);
                              _replace(phrase.copyWith(clearRecording: true));
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить запись'),
                    ),
                    TextButton.icon(
                      onPressed: _phrases.length == 1
                          ? null
                          : () => _delete(phrase),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Удалить фразу'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => setState(
        () => _phrases.add(
          TrainingPhrase(id: TrainingPhrase.newId(), text: 'Новая фраза'),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Добавить'),
    ),
  );

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
