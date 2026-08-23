// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Parrot Trainer';

  @override
  String get about => 'О программе';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get aboutDescription =>
      'Тренажёр повторяет фразы в ответ на звуки и во время тишины.';

  @override
  String get resetSettings => 'Сбросить настройки';

  @override
  String get resetStatistics => 'Сбросить статистику';

  @override
  String get privacyTitle => 'Политика конфиденциальности';

  @override
  String get privacyBody =>
      'Parrot Trainer использует микрофон для определения звуков и позволяет записывать фразы для обучения. Записи, настройки и статистика хранятся локально на устройстве.\n\nВыбранный в Android сервис распознавания речи может обрабатывать аудио согласно своей политике. У Parrot Trainer нет собственного сервера, и он не отправляет записи на него.\n\nПриложение не показывает рекламу и не продаёт ваши данные.';
}
