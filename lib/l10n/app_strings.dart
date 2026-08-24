import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// Short UI strings which are shared by screens that do not need parameters.
/// ARB continues to own application metadata and the privacy policy.
class AppStrings {
  AppStrings._(this._english);

  final bool _english;

  static AppStrings of(BuildContext context) =>
      AppStrings._(AppLocalizations.of(context)?.localeName == 'en');

  String get phrases => _english ? 'Training phrases' : 'Фразы для обучения';
  String get edit => _english ? 'Edit' : 'Редактировать';
  String get learningNow => _english ? 'Learning now:' : 'Изучаем сейчас:';
  String get allPhrases => _english ? 'All phrases' : 'Все фразы';
  String get microphone => _english ? 'Microphone & sound' : 'Микрофон и звук';
  String get soundLevel => _english ? 'Sound level' : 'Уровень звука';
  String get hearingSound => _english ? 'SOUND DETECTED' : 'СЛЫШУ ЗВУК';
  String get silence => _english ? 'Silence' : 'Тишина';
  String get threshold =>
      _english ? 'Detection threshold' : 'Порог срабатывания';
  String get calibrateMicrophone =>
      _english ? 'Calibrate microphone' : 'Калибровать микрофон';
  String calibration(int seconds) =>
      _english ? 'Calibrating… $seconds sec' : 'Калибровка… $seconds сек';
  String get intervals => _english ? 'Pauses & intervals' : 'Паузы и интервалы';
  String get minimumInterval =>
      _english ? 'Minimum interval' : 'Минимальный интервал';
  String get startConversation =>
      _english ? 'Start a conversation' : 'Инициировать разговор';
  String get responsePause =>
      _english ? 'Pause for a response' : 'Пауза для ответа';
  String get seconds => _english ? 'sec' : 'сек';
  String get schedule => _english ? 'Schedule' : 'Время работы';
  String get followSchedule =>
      _english ? 'Follow a schedule' : 'Работать по расписанию';
  String get scheduleDescription => _english
      ? 'Training stops outside these hours'
      : 'Вне этого времени тренировка выключается';
  String get start => _english ? 'Start' : 'Начало';
  String get end => _english ? 'End' : 'Окончание';
  String get allowScreenSleep =>
      _english ? 'Allow screen to turn off' : 'Разрешить выключение экрана';
  String get screenSleepDescription => _english
      ? 'Training continues with a status-bar notification'
      : 'Тренировка продолжится с уведомлением в строке состояния';
  String get voiceAndSpeech => _english ? 'Voice & speech' : 'Голос и речь';
  String get defaultAndroidVoice =>
      _english ? 'Default Android voice' : 'Голос Android по умолчанию';
  String selectedVoices(int count) =>
      _english ? 'Selected voices: $count' : 'Выбрано голосов: $count';
  String get goodAttempt => _english ? 'Good attempt' : 'Хорошая попытка';
  String get statistics => _english ? 'Statistics' : 'Статистика';
  String get phrasesSpoken => _english ? 'Phrases spoken' : 'Сказано фраз';
  String get responsesToChirps =>
      _english ? 'Responses to chirps' : 'В ответ на чириканье';
  String get programOn => _english ? 'TRAINING IS ON' : 'ПРОГРАММА ВКЛЮЧЕНА';
  String get programOff => _english ? 'TRAINING IS OFF' : 'ПРОГРАММА ВЫКЛЮЧЕНА';
  String get speaking => _english ? 'Speaking…' : 'Говорю…';
  String get waitingForSilence =>
      _english ? 'Waiting for silence' : 'Жду тишины';
  String nextPhraseIn(int seconds) => _english
      ? 'Next phrase in $seconds seconds'
      : 'Следующая фраза через $seconds секунд';
  String get microphoneNeeded => _english
      ? 'Microphone access is required to measure sound.'
      : 'Для измерения звука нужен доступ к микрофону.';
  String get retry => _english ? 'Retry' : 'Повторить';
  String get microphoneDenied => _english
      ? 'Microphone access was not granted. Allow it in Android settings.'
      : 'Доступ к микрофону не предоставлен. Разрешите его в настройках Android.';
  String get outsideSchedule => _english
      ? 'This is outside the configured training schedule.'
      : 'Сейчас вне установленного времени обучения.';
  String get cannotStartWithoutMicrophone => _english
      ? 'Training cannot start without microphone access.'
      : 'Без доступа к микрофону тренировка не может быть запущена.';
  String get phrase => _english ? 'Phrase' : 'Фраза';
  String get save => _english ? 'Save' : 'Сохранить';
  String get record => _english ? 'Record' : 'Записать';
  String get stop => _english ? 'Stop' : 'Остановить';
  String get listen => _english ? 'Listen' : 'Прослушать';
  String get deleteRecording =>
      _english ? 'Delete recording' : 'Удалить запись';
  String get deletePhrase => _english ? 'Delete phrase' : 'Удалить фразу';
  String get text => _english ? 'Text' : 'Текст';
  String get voice => _english ? 'Voice' : 'Голос';
  String get recognitionUnavailable => _english
      ? 'Speech recognition is unavailable; using standard recording.'
      : 'Распознавание недоступно, используется обычная запись';
  String get recordingStartFailed =>
      _english ? 'Could not start recording' : 'Не удалось начать запись';
  String get recordingSavedRecognitionFailed => _english
      ? 'Recording saved, but speech recognition failed'
      : 'Запись сохранена, но речь распознать не удалось';
  String get recordingFailed =>
      _english ? 'Could not record audio' : 'Не удалось записать звук';
  String get enterTextForRecordedPhrases => _english
      ? 'Enter text for each recorded phrase'
      : 'Введите текст для каждой записанной фразы';
  String get addAtLeastOnePhrase => _english
      ? 'Add at least one phrase'
      : 'Добавьте хотя бы одну фразу';
  String get recordedPhraseTextRequired => _english
      ? 'Enter text for the recorded phrase'
      : 'Введите текст записанной фразы';
  String get voiceSettings => _english ? 'Speech settings' : 'Настройки речи';
  String get speechRate => _english ? 'Speech rate' : 'Скорость речи';
  String get pitch => _english ? 'Pitch' : 'Высота голоса';
  String get volume => _english ? 'Volume' : 'Громкость';
  String get testSound => _english ? 'Test sound' : 'Проверить звучание';
  String get installedVoices =>
      _english ? 'Installed voices' : 'Установленные голоса';
  String get voiceSelectionHint => _english
      ? 'Choose several voices. If none are selected, the default Android voice is used.'
      : 'Можно выбрать несколько. Если ничего не выбрано, используется голос Android по умолчанию.';
  String get voiceFilter => _english ? 'Voice filter' : 'Фильтр голосов';
  String get voiceFilterHint =>
      _english ? 'For example, en or English' : 'Например, ru или Russian';
  String get noVoices => _english
      ? 'Android did not report any installed TTS voices. Check text-to-speech settings.'
      : 'Android не сообщил об установленных TTS-голосах. Проверьте настройки синтеза речи.';
  String get noFilteredVoices => _english
      ? 'No voices match this filter.'
      : 'По этому фильтру голоса не найдены.';
  String get activity => _english ? 'Activity' : 'Активность';
  String get previousMonth => _english ? 'Previous month' : 'Предыдущий месяц';
  String get nextMonth => _english ? 'Next month' : 'Следующий месяц';
  String get noHistory => _english
      ? 'Training history is empty.\nIt will appear after the next training session.'
      : 'История тренировок пока пуста.\nОна появится после следующей тренировки.';
  String get noDayData => _english
      ? 'No training data for this day.'
      : 'Нет данных о тренировках за этот день.';
  String statisticsFor(String date) =>
      _english ? 'Statistics for $date' : 'Статистика за $date';
  String sounds(int count) => _english ? '$count sounds' : '$count звуков';
  String get parrotReplied => _english ? 'Parrot replied' : 'Попугай ответил';
  String get trainingTime => _english ? 'Training time' : 'Время тренировки';
  String get activityByTime =>
      _english ? 'Activity by time' : 'Активность по времени';
  String get trainingWithoutSounds =>
      _english ? 'training without sounds' : 'тренировка без звуков';
  String get noDataShort => _english ? 'no data' : 'нет данных';
  String get activityOff => _english ? 'off' : 'выкл.';
  String get activityRunningQuiet =>
      _english ? 'running, quiet' : 'работала, тихо';
  String get activityLegend => _english ? 'activity' : 'активность';
  String get trainingRunningNoSounds => _english
      ? 'Training is running, no sounds'
      : 'Тренировка работала, звуков нет';
  String get trainingStopped =>
      _english ? 'Training is off' : 'Тренировка выключена';
  List<String> get weekdays => _english
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  List<String> get months => _english
      ? const [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ]
      : const [
          'Январь',
          'Февраль',
          'Март',
          'Апрель',
          'Май',
          'Июнь',
          'Июль',
          'Август',
          'Сентябрь',
          'Октябрь',
          'Ноябрь',
          'Декабрь',
        ];
  String duration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return _english
        ? (h > 0 ? '${h}h ${m}m' : '${m}m')
        : (h > 0 ? '$h ч $m мин' : '$m мин');
  }
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
