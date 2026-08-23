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
      'Parrot Trainer использует микрофон для определения звуков, записи фраз и опционального распознавания речи. Звук при обычном мониторинге обрабатывается в памяти и намеренно не сохраняется. Записи, которые вы явно создаёте, настройки и статистика хранятся в приватном хранилище приложения на устройстве.\n\nВыбранные в Android сервисы распознавания речи и синтеза речи могут обрабатывать аудио или текст фраз локально либо удалённо согласно собственным политикам. У Parrot Trainer нет серверной части разработчика, рекламы или аналитики; приложение не продаёт ваши данные.\n\nВы можете удалить записи, сбросить настройки и статистику, очистить данные приложения или удалить приложение. Android может резервировать часть настроек и статистики в соответствии с настройками устройства; аудиозаписи фраз исключены из правил резервного копирования Parrot Trainer.\n\nВопросы о конфиденциальности: https://github.com/DimonSmart/ParrotTrainer/issues';
}
