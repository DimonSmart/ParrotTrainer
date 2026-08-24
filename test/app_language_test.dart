import 'package:flutter_test/flutter_test.dart';
import 'package:parrot_trainer/l10n/app_language.dart';
import 'package:parrot_trainer/models/training_settings.dart';

void main() {
  test('supported languages resolve directly', () {
    expect(AppLanguage.resolve('en'), AppLanguage.english);
    expect(AppLanguage.resolve('ru'), AppLanguage.russian);
    expect(AppLanguage.resolve('es'), AppLanguage.spanish);
    expect(AppLanguage.resolve('ES'), AppLanguage.spanish);
  });

  test('unsupported languages fall back to English', () {
    expect(AppLanguage.resolve('de'), AppLanguage.english);
    expect(AppLanguage.resolve(null), AppLanguage.english);
  });

  test('Spanish defaults use Spanish phrases', () {
    final settings = TrainingSettings.defaultsFor('es');
    expect(settings.phrases.map((phrase) => phrase.text), [
      '¡Hola!',
      '¡Buen pajarito!',
      '¡Qué bonito pajarito!',
    ]);
  });

  test('unsupported locale defaults use English phrases', () {
    final settings = TrainingSettings.defaultsFor('de');
    expect(settings.phrases.map((phrase) => phrase.text), [
      'Hello!',
      'Good bird!',
      'Pretty bird!',
    ]);
  });
}
