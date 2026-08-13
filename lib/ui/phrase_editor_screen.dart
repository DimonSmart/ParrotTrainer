import 'package:flutter/material.dart';

class PhraseEditorScreen extends StatefulWidget {
  const PhraseEditorScreen({super.key, required this.phrases});
  final List<String> phrases;

  @override
  State<PhraseEditorScreen> createState() => _PhraseEditorScreenState();
}

class _PhraseEditorScreenState extends State<PhraseEditorScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.phrases.join('\n\n'),
  );

  void _save() {
    final phrases = _controller.text
        .split(RegExp(r'\n\s*\n+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (phrases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одну фразу')),
      );
      return;
    }
    Navigator.pop(context, phrases);
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
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: TextField(
        controller: _controller,
        autofocus: true,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          hintText: 'Введите фразы, разделяя их пустой строкой',
          helperText: 'Каждая фраза отделяется пустой строкой',
          alignLabelWithHint: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _save,
      icon: const Icon(Icons.save),
      label: const Text('Сохранить'),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
