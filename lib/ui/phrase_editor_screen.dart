import 'dart:async';

import 'package:flutter/material.dart';

import '../models/training_phrase.dart';
import '../services/phrase_recorder.dart';
import '../services/recorded_phrase_player.dart';
import '../services/speech_recognition_service.dart';

class PhraseEditorScreen extends StatefulWidget {
  const PhraseEditorScreen({
    super.key,
    required this.phrases,
    this.recorder,
    this.speechRecognition,
    this.player,
  });

  final List<TrainingPhrase> phrases;
  final PhraseRecordingService? recorder;
  final SpeechRecognitionService? speechRecognition;
  final RecordedPhrasePlayer? player;

  @override
  State<PhraseEditorScreen> createState() => _PhraseEditorScreenState();
}

class _PhraseEditorScreenState extends State<PhraseEditorScreen> {
  late final PhraseRecordingService _recorder;
  late final SpeechRecognitionService _speechRecognition;
  late final RecordedPhrasePlayer _player;
  late final List<TrainingPhrase> _phrases = List.of(widget.phrases);
  final Map<String, TextEditingController> _textControllers = {};
  final Set<String> _emptyRecordedPhraseIds = {};
  String? _recordingId;
  bool _recognitionActive = false;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? PhraseRecorder();
    _speechRecognition =
        widget.speechRecognition ?? SystemSpeechRecognitionService();
    _player = widget.player ?? LocalRecordedPhrasePlayer();
    for (final phrase in _phrases) {
      _textControllers[phrase.id] = TextEditingController(text: phrase.text);
    }
  }

  TrainingPhrase _current(String id) =>
      _phrases.firstWhere((phrase) => phrase.id == id);

  Future<void> _toggleRecording(TrainingPhrase phrase) async {
    if (_recordingId == phrase.id) {
      await _stopRecording(phrase.id);
      return;
    }
    if (_recordingId != null) return;

    try {
      try {
        await _speechRecognition.start(phrase.id);
        _recognitionActive = true;
      } catch (_) {
        await _recorder.start(phrase.id);
        _recognitionActive = false;
      }
      if (mounted) setState(() => _recordingId = phrase.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось начать запись')));
    }
  }

  Future<void> _stopRecording(String phraseId) async {
    try {
      String? audioPath;
      String? recognizedText;
      Object? recognitionError;
      if (_recognitionActive) {
        final result = await _speechRecognition.stop();
        audioPath = result.audioPath;
        recognizedText = result.text?.trim();
        recognitionError = result.error;
      } else {
        audioPath = await _recorder.stop();
      }

      final phrase = _current(phraseId);
      final shouldFillText =
          phrase.text.trim().isEmpty &&
          recognizedText != null &&
          recognizedText.isNotEmpty;
      final updated = phrase.copyWith(
        recordedAudioPath: audioPath,
        text: shouldFillText ? recognizedText : null,
      );
      if (shouldFillText) {
        _textControllers[phraseId]!.text = recognizedText;
      }
      _replace(updated);
      if (recognitionError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запись сохранена, но речь распознать не удалось'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось завершить запись')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _recordingId = null;
          _recognitionActive = false;
        });
      }
    }
  }

  void _replace(TrainingPhrase phrase) {
    final index = _phrases.indexWhere((item) => item.id == phrase.id);
    if (index >= 0) setState(() => _phrases[index] = phrase);
  }

  void _addTextPhrase() {
    final phrase = TrainingPhrase(id: TrainingPhrase.newId(), text: '');
    _textControllers[phrase.id] = TextEditingController();
    setState(() => _phrases.add(phrase));
  }

  Future<void> _addVoicePhrase() async {
    final phrase = TrainingPhrase(id: TrainingPhrase.newId(), text: '');
    _textControllers[phrase.id] = TextEditingController();
    setState(() => _phrases.add(phrase));
    await _toggleRecording(phrase);
  }

  Future<void> _delete(TrainingPhrase phrase) async {
    await _recorder.delete(phrase.recordedAudioPath);
    _textControllers.remove(phrase.id)?.dispose();
    setState(() => _phrases.removeWhere((item) => item.id == phrase.id));
  }

  void _save() {
    final invalidRecorded = _phrases
        .where(
          (phrase) =>
              phrase.recordedAudioPath != null && phrase.text.trim().isEmpty,
        )
        .map((phrase) => phrase.id)
        .toSet();
    if (invalidRecorded.isNotEmpty) {
      setState(() {
        _emptyRecordedPhraseIds
          ..clear()
          ..addAll(invalidRecorded);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите текст для каждой записанной фразы'),
        ),
      );
      return;
    }
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
          key: const Key('savePhrases'),
          onPressed: _recordingId == null ? _save : null,
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
        final anotherRecording = _recordingId != null && !recording;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  key: Key('phraseText-${phrase.id}'),
                  controller: _textControllers[phrase.id],
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText: 'Фраза',
                    errorText: _emptyRecordedPhraseIds.contains(phrase.id)
                        ? 'Введите текст записанной фразы'
                        : null,
                  ),
                  onChanged: (text) {
                    _emptyRecordedPhraseIds.remove(phrase.id);
                    _replace(_current(phrase.id).copyWith(text: text));
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: Key('recordPhrase-${phrase.id}'),
                      onPressed: anotherRecording
                          ? null
                          : () => _toggleRecording(phrase),
                      icon: Icon(recording ? Icons.stop : Icons.mic),
                      label: Text(recording ? 'Остановить' : 'Записать'),
                    ),
                    TextButton.icon(
                      onPressed:
                          phrase.recordedAudioPath == null ||
                              _recordingId != null
                          ? null
                          : () => _player.playIfAvailable(
                              phrase.recordedAudioPath,
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Прослушать'),
                    ),
                    TextButton.icon(
                      onPressed:
                          phrase.recordedAudioPath == null ||
                              _recordingId != null
                          ? null
                          : () async {
                              await _recorder.delete(phrase.recordedAudioPath);
                              _replace(phrase.copyWith(clearRecording: true));
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить запись'),
                    ),
                    TextButton.icon(
                      onPressed: _phrases.length == 1 || _recordingId != null
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
    floatingActionButton: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          key: const Key('addTextPhrase'),
          heroTag: 'addTextPhrase',
          onPressed: _recordingId == null ? _addTextPhrase : null,
          icon: const Icon(Icons.add),
          label: const Text('Текст'),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          key: const Key('addVoicePhrase'),
          heroTag: 'addVoicePhrase',
          onPressed: _recordingId == null ? _addVoicePhrase : null,
          icon: const Icon(Icons.mic),
          label: const Text('Голос'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    if (_recordingId != null && _recognitionActive) {
      unawaited(_speechRecognition.cancel());
    }
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    unawaited(_recorder.dispose());
    unawaited(_speechRecognition.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }
}
