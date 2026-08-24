import 'dart:async';

import 'package:flutter/material.dart';

import '../models/training_phrase.dart';
import '../services/phrase_recorder.dart';
import '../services/recorded_phrase_player.dart';
import '../services/speech_recognition_service.dart';
import '../l10n/app_strings.dart';

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

class _PhraseEditorScreenState extends State<PhraseEditorScreen>
    with WidgetsBindingObserver {
  late final PhraseRecordingService _recorder;
  late final SpeechRecognitionService _speechRecognition;
  late final RecordedPhrasePlayer _player;
  late final List<TrainingPhrase> _phrases = List.of(widget.phrases);
  final Map<String, TextEditingController> _textControllers = {};
  final Set<String> _emptyRecordedPhraseIds = {};
  final ScrollController _scrollController = ScrollController();
  String? _recordingId;
  String? _newVoiceRecordingId;
  bool _recognitionActive = false;
  bool _coordinatedRecordingUnavailable = false;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? PhraseRecorder();
    _speechRecognition =
        widget.speechRecognition ?? SystemSpeechRecognitionService();
    _player = widget.player ?? LocalRecordedPhrasePlayer();
    WidgetsBinding.instance.addObserver(this);
    for (final phrase in _phrases) {
      _textControllers[phrase.id] = TextEditingController(text: phrase.text);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_cancelRecordingForBackground());
    }
  }

  Future<void> _cancelRecordingForBackground() async {
    if (_recordingId == null) return;
    try {
      if (_recognitionActive) {
        await _speechRecognition.cancel();
      } else {
        await _recorder.cancel();
      }
    } finally {
      if (mounted) {
        setState(() {
          _recordingId = null;
          _newVoiceRecordingId = null;
          _recognitionActive = false;
        });
      }
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

    await _startRecording(phrase.id);
  }

  Future<void> _toggleNewVoiceRecording() async {
    final pendingId = _newVoiceRecordingId;
    if (pendingId != null && _recordingId == pendingId) {
      await _stopRecording(pendingId, createPhrase: true);
      return;
    }
    if (_recordingId != null) return;

    await _startRecording(TrainingPhrase.newId(), isNewVoice: true);
  }

  Future<void> _startRecording(
    String phraseId, {
    bool isNewVoice = false,
  }) async {
    if (_recordingId != null) return;

    try {
      if (!_coordinatedRecordingUnavailable) {
        try {
          await _speechRecognition.start(phraseId);
          _recognitionActive = true;
        } catch (_) {
          await _speechRecognition.cancel();
          _coordinatedRecordingUnavailable = true;
        }
      }
      if (!_recognitionActive) {
        await _recorder.start(phraseId);
        if (mounted && _coordinatedRecordingUnavailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.strings.recognitionUnavailable)),
          );
        }
      }
      if (mounted) {
        setState(() {
          _recordingId = phraseId;
          _newVoiceRecordingId = isNewVoice ? phraseId : null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.recordingStartFailed)),
      );
    }
  }

  Future<void> _stopRecording(
    String phraseId, {
    bool createPhrase = false,
  }) async {
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

      if (createPhrase) {
        if (audioPath == null) throw const EmptyAudioRecordingException();
        final text = recognizedText ?? '';
        final phrase = TrainingPhrase(
          id: phraseId,
          text: text,
          recordedAudioPath: audioPath,
        );
        _textControllers[phraseId] = TextEditingController(text: text);
        if (mounted) {
          setState(() => _phrases.add(phrase));
          _scrollToBottom();
        }
      } else {
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
      }
      if (recognitionError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.recordingSavedRecognitionFailed)),
        );
      }
    } on EmptyAudioRecordingException {
      _coordinatedRecordingUnavailable = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.recordingFailed)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.recordingFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _recordingId = null;
          _newVoiceRecordingId = null;
          _recognitionActive = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
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
        SnackBar(content: Text(context.strings.enterTextForRecordedPhrases)),
      );
      return;
    }
    final valid = _phrases
        .where((phrase) => phrase.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.addAtLeastOnePhrase)),
      );
      return;
    }
    Navigator.pop(context, valid);
  }

  @override
  Widget build(BuildContext context) {
    final recordingNewVoice =
        _newVoiceRecordingId != null && _recordingId == _newVoiceRecordingId;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.phrases),
        actions: [
          IconButton(
            key: const Key('savePhrases'),
            onPressed: _recordingId == null ? _save : null,
            icon: const Icon(Icons.check),
            tooltip: context.strings.save,
          ),
        ],
      ),
      body: ListView.builder(
        controller: _scrollController,
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
                      labelText: context.strings.phrase,
                      errorText: _emptyRecordedPhraseIds.contains(phrase.id)
                          ? context.strings.recordedPhraseTextRequired
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
                        label: Text(
                          recording
                              ? context.strings.stop
                              : context.strings.record,
                        ),
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
                        label: Text(context.strings.listen),
                      ),
                      TextButton.icon(
                        onPressed:
                            phrase.recordedAudioPath == null ||
                                _recordingId != null
                            ? null
                            : () async {
                                await _recorder.delete(
                                  phrase.recordedAudioPath,
                                );
                                _replace(phrase.copyWith(clearRecording: true));
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(context.strings.deleteRecording),
                      ),
                      TextButton.icon(
                        onPressed: _phrases.length == 1 || _recordingId != null
                            ? null
                            : () => _delete(phrase),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: Text(context.strings.deletePhrase),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('addTextPhrase'),
                  onPressed: _recordingId == null ? _addTextPhrase : null,
                  icon: const Icon(Icons.add),
                  label: Text(context.strings.text),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('addVoicePhrase'),
                  onPressed: _recordingId == null || recordingNewVoice
                      ? _toggleNewVoiceRecording
                      : null,
                  icon: Icon(recordingNewVoice ? Icons.stop : Icons.mic),
                  label: Text(
                    recordingNewVoice
                        ? context.strings.stop
                        : context.strings.voice,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_recordingId != null && _recognitionActive) {
      unawaited(_speechRecognition.cancel());
    } else if (_recordingId != null) {
      unawaited(_recorder.cancel());
    }
    _scrollController.dispose();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    unawaited(_recorder.dispose());
    unawaited(_speechRecognition.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }
}
