import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/controllers/app_controller.dart';
import 'package:parrot_trainer/l10n/generated/app_localizations.dart';
import 'package:parrot_trainer/models/training_settings.dart';
import 'package:parrot_trainer/services/tts_service.dart';
import 'package:parrot_trainer/ui/voices_screen.dart';

void main() {
  testWidgets('filters voices by name and locale without case sensitivity', (
    tester,
  ) async {
    final controller = AppController(tts: _FakeTts());
    controller.voices = const [
      TtsVoice(name: 'Russian voice', locale: 'ru-RU'),
      TtsVoice(name: 'English voice', locale: 'en-US'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: VoicesScreen(controller: controller),
      ),
    );

    await tester.enterText(find.byKey(const Key('voiceFilter')), 'RU');
    await tester.pump();

    expect(find.text('Russian voice'), findsOneWidget);
    expect(find.text('English voice'), findsNothing);

    await tester.enterText(find.byKey(const Key('voiceFilter')), 'missing');
    await tester.pump();

    expect(find.text('По этому фильтру голоса не найдены.'), findsOneWidget);
  });
}

class _FakeTts implements TtsService {
  @override
  Future<List<TtsVoice>> getVoices() async => [];

  @override
  Future<void> speak(
    String phrase,
    TrainingSettings settings,
    TtsVoice? voice,
  ) async {}

  @override
  Future<void> stop() async {}
}
