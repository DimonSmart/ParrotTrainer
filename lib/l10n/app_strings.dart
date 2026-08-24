import 'package:flutter/widgets.dart';

import 'app_language.dart';
import 'generated/app_localizations.dart';

/// Short UI strings which are shared by screens that do not need parameters.
/// ARB continues to own application metadata and the privacy policy.
class AppStrings {
  AppStrings._(this._language);

  final AppLanguage _language;

  static AppStrings of(BuildContext context) => AppStrings._(
    AppLanguage.resolve(
      AppLocalizations.of(context)?.localeName ??
          Localizations.localeOf(context).languageCode,
    ),
  );

  T _pick<T>(T english, T russian, T spanish) => switch (_language) {
    AppLanguage.english => english,
    AppLanguage.russian => russian,
    AppLanguage.spanish => spanish,
  };

  String get phrases =>
      _pick('Training phrases', 'Фразы для обучения', 'Frases de entrenamiento');
  String get edit => _pick('Edit', 'Редактировать', 'Editar');
  String get learningNow =>
      _pick('Learning now:', 'Изучаем сейчас:', 'Aprendiendo ahora:');
  String get allPhrases =>
      _pick('All phrases', 'Все фразы', 'Todas las frases');
  String get microphone =>
      _pick('Microphone & sound', 'Микрофон и звук', 'Micrófono y sonido');
  String get soundLevel =>
      _pick('Sound level', 'Уровень звука', 'Nivel de sonido');
  String get hearingSound =>
      _pick('SOUND DETECTED', 'СЛЫШУ ЗВУК', 'SONIDO DETECTADO');
  String get silence => _pick('Silence', 'Тишина', 'Silencio');
  String get threshold => _pick(
    'Detection threshold',
    'Порог срабатывания',
    'Umbral de detección',
  );
  String get calibrateMicrophone => _pick(
    'Calibrate microphone',
    'Калибровать микрофон',
    'Calibrar micrófono',
  );
  String calibration(int seconds) => _pick(
    'Calibrating… $seconds sec',
    'Калибровка… $seconds сек',
    'Calibrando… $seconds s',
  );
  String get intervals =>
      _pick('Pauses & intervals', 'Паузы и интервалы', 'Pausas e intervalos');
  String get minimumInterval => _pick(
    'Minimum interval',
    'Минимальный интервал',
    'Intervalo mínimo',
  );
  String get startConversation => _pick(
    'Start a conversation',
    'Инициировать разговор',
    'Iniciar una conversación',
  );
  String get responsePause => _pick(
    'Pause for a response',
    'Пауза для ответа',
    'Pausa para responder',
  );
  String get seconds => _pick('sec', 'сек', 's');
  String get schedule => _pick('Schedule', 'Время работы', 'Horario');
  String get followSchedule => _pick(
    'Follow a schedule',
    'Работать по расписанию',
    'Seguir un horario',
  );
  String get scheduleDescription => _pick(
    'Training stops outside these hours',
    'Вне этого времени тренировка выключается',
    'El entrenamiento se detiene fuera de este horario',
  );
  String get start => _pick('Start', 'Начало', 'Inicio');
  String get end => _pick('End', 'Окончание', 'Fin');
  String get allowScreenSleep => _pick(
    'Allow screen to turn off',
    'Разрешить выключение экрана',
    'Permitir que se apague la pantalla',
  );
  String get screenSleepDescription => _pick(
    'Training continues with a status-bar notification',
    'Тренировка продолжится с уведомлением в строке состояния',
    'El entrenamiento continúa con una notificación en la barra de estado',
  );
  String get voiceAndSpeech =>
      _pick('Voice & speech', 'Голос и речь', 'Voz y habla');
  String get defaultAndroidVoice => _pick(
    'Default Android voice',
    'Голос Android по умолчанию',
    'Voz predeterminada de Android',
  );
  String selectedVoices(int count) => _pick(
    'Selected voices: $count',
    'Выбрано голосов: $count',
    'Voces seleccionadas: $count',
  );
  String get goodAttempt =>
      _pick('Good attempt', 'Хорошая попытка', 'Buen intento');
  String get statistics => _pick('Statistics', 'Статистика', 'Estadísticas');
  String get phrasesSpoken =>
      _pick('Phrases spoken', 'Сказано фраз', 'Frases pronunciadas');
  String get responsesToChirps => _pick(
    'Responses to chirps',
    'В ответ на чириканье',
    'Respuestas a los trinos',
  );
  String get programOn => _pick(
    'TRAINING IS ON',
    'ПРОГРАММА ВКЛЮЧЕНА',
    'ENTRENAMIENTO ACTIVADO',
  );
  String get programOff => _pick(
    'TRAINING IS OFF',
    'ПРОГРАММА ВЫКЛЮЧЕНА',
    'ENTRENAMIENTO DESACTIVADO',
  );
  String get speaking => _pick('Speaking…', 'Говорю…', 'Hablando…');
  String get waitingForSilence => _pick(
    'Waiting for silence',
    'Жду тишины',
    'Esperando silencio',
  );
  String nextPhraseIn(int seconds) => _pick(
    'Next phrase in $seconds seconds',
    'Следующая фраза через $seconds секунд',
    'Próxima frase en $seconds segundos',
  );
  String get microphoneNeeded => _pick(
    'Microphone access is required to measure sound.',
    'Для измерения звука нужен доступ к микрофону.',
    'Se necesita acceso al micrófono para medir el sonido.',
  );
  String get retry => _pick('Retry', 'Повторить', 'Reintentar');
  String get microphoneDenied => _pick(
    'Microphone access was not granted. Allow it in Android settings.',
    'Доступ к микрофону не предоставлен. Разрешите его в настройках Android.',
    'No se concedió acceso al micrófono. Permítelo en los ajustes de Android.',
  );
  String get outsideSchedule => _pick(
    'This is outside the configured training schedule.',
    'Сейчас вне установленного времени обучения.',
    'Ahora estás fuera del horario de entrenamiento configurado.',
  );
  String get cannotStartWithoutMicrophone => _pick(
    'Training cannot start without microphone access.',
    'Без доступа к микрофону тренировка не может быть запущена.',
    'El entrenamiento no puede empezar sin acceso al micrófono.',
  );
  String get phrase => _pick('Phrase', 'Фраза', 'Frase');
  String get save => _pick('Save', 'Сохранить', 'Guardar');
  String get record => _pick('Record', 'Записать', 'Grabar');
  String get stop => _pick('Stop', 'Остановить', 'Detener');
  String get listen => _pick('Listen', 'Прослушать', 'Escuchar');
  String get deleteRecording =>
      _pick('Delete recording', 'Удалить запись', 'Eliminar grabación');
  String get deletePhrase =>
      _pick('Delete phrase', 'Удалить фразу', 'Eliminar frase');
  String get text => _pick('Text', 'Текст', 'Texto');
  String get voice => _pick('Voice', 'Голос', 'Voz');
  String get recognitionUnavailable => _pick(
    'Speech recognition is unavailable; using standard recording.',
    'Распознавание недоступно, используется обычная запись',
    'El reconocimiento de voz no está disponible; se usará la grabación normal.',
  );
  String get recordingStartFailed => _pick(
    'Could not start recording',
    'Не удалось начать запись',
    'No se pudo iniciar la grabación',
  );
  String get recordingSavedRecognitionFailed => _pick(
    'Recording saved, but speech recognition failed',
    'Запись сохранена, но речь распознать не удалось',
    'La grabación se guardó, pero falló el reconocimiento de voz',
  );
  String get recordingFailed => _pick(
    'Could not record audio',
    'Не удалось записать звук',
    'No se pudo grabar el audio',
  );
  String get enterTextForRecordedPhrases => _pick(
    'Enter text for each recorded phrase',
    'Введите текст для каждой записанной фразы',
    'Introduce texto para cada frase grabada',
  );
  String get addAtLeastOnePhrase => _pick(
    'Add at least one phrase',
    'Добавьте хотя бы одну фразу',
    'Añade al menos una frase',
  );
  String get recordedPhraseTextRequired => _pick(
    'Enter text for the recorded phrase',
    'Введите текст записанной фразы',
    'Introduce texto para la frase grabada',
  );
  String get voiceSettings =>
      _pick('Speech settings', 'Настройки речи', 'Ajustes de voz');
  String get speechRate =>
      _pick('Speech rate', 'Скорость речи', 'Velocidad del habla');
  String get pitch => _pick('Pitch', 'Высота голоса', 'Tono');
  String get volume => _pick('Volume', 'Громкость', 'Volumen');
  String get testSound =>
      _pick('Test sound', 'Проверить звучание', 'Probar sonido');
  String get installedVoices =>
      _pick('Installed voices', 'Установленные голоса', 'Voces instaladas');
  String get voiceSelectionHint => _pick(
    'Choose several voices. If none are selected, the default Android voice is used.',
    'Можно выбрать несколько. Если ничего не выбрано, используется голос Android по умолчанию.',
    'Puedes elegir varias voces. Si no seleccionas ninguna, se usará la voz predeterminada de Android.',
  );
  String get voiceFilter =>
      _pick('Voice filter', 'Фильтр голосов', 'Filtro de voces');
  String get voiceFilterHint => _pick(
    'For example, en or English',
    'Например, ru или Russian',
    'Por ejemplo, es o español',
  );
  String get noVoices => _pick(
    'Android did not report any installed TTS voices. Check text-to-speech settings.',
    'Android не сообщил об установленных TTS-голосах. Проверьте настройки синтеза речи.',
    'Android no informó de ninguna voz TTS instalada. Comprueba los ajustes de texto a voz.',
  );
  String get noFilteredVoices => _pick(
    'No voices match this filter.',
    'По этому фильтру голоса не найдены.',
    'Ninguna voz coincide con este filtro.',
  );
  String get activity => _pick('Activity', 'Активность', 'Actividad');
  String get previousMonth =>
      _pick('Previous month', 'Предыдущий месяц', 'Mes anterior');
  String get nextMonth =>
      _pick('Next month', 'Следующий месяц', 'Mes siguiente');
  String get noHistory => _pick(
    'Training history is empty.\nIt will appear after the next training session.',
    'История тренировок пока пуста.\nОна появится после следующей тренировки.',
    'El historial de entrenamiento está vacío.\nAparecerá después de la próxima sesión de entrenamiento.',
  );
  String get noDayData => _pick(
    'No training data for this day.',
    'Нет данных о тренировках за этот день.',
    'No hay datos de entrenamiento para este día.',
  );
  String statisticsFor(String date) => _pick(
    'Statistics for $date',
    'Статистика за $date',
    'Estadísticas del $date',
  );
  String sounds(int count) =>
      _pick('$count sounds', '$count звуков', '$count sonidos');
  String get parrotReplied =>
      _pick('Parrot replied', 'Попугай ответил', 'El loro respondió');
  String get trainingTime =>
      _pick('Training time', 'Время тренировки', 'Tiempo de entrenamiento');
  String get activityByTime =>
      _pick('Activity by time', 'Активность по времени', 'Actividad por hora');
  String get trainingWithoutSounds => _pick(
    'training without sounds',
    'тренировка без звуков',
    'entrenamiento sin sonidos',
  );
  String get noDataShort => _pick('no data', 'нет данных', 'sin datos');
  String get activityOff => _pick('off', 'выкл.', 'apagado');
  String get activityRunningQuiet =>
      _pick('running, quiet', 'работала, тихо', 'activo, en silencio');
  String get activityLegend => _pick('activity', 'активность', 'actividad');
  String get trainingRunningNoSounds => _pick(
    'Training is running, no sounds',
    'Тренировка работала, звуков нет',
    'Entrenamiento activo, sin sonidos',
  );
  String get trainingStopped => _pick(
    'Training is off',
    'Тренировка выключена',
    'Entrenamiento desactivado',
  );
  List<String> get weekdays => _pick(
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
    const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'],
  );
  List<String> get months => _pick(
    const [
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
    ],
    const [
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
    ],
    const [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ],
  );
  String duration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return _pick(
      h > 0 ? '${h}h ${m}m' : '${m}m',
      h > 0 ? '$h ч $m мин' : '$m мин',
      h > 0 ? '$h h $m min' : '$m min',
    );
  }
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
