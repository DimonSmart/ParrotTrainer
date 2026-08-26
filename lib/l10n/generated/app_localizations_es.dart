// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Parrot Trainer';

  @override
  String get about => 'Acerca de';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get aboutDescription =>
      'Un asistente de entrenamiento que repite frases en respuesta a sonidos y durante los periodos de silencio.';

  @override
  String get resetSettings => 'Restablecer ajustes';

  @override
  String get resetStatistics => 'Restablecer estadísticas';

  @override
  String get privacyTitle => 'Política de privacidad';

  @override
  String get privacyBody =>
      'Parrot Trainer utiliza el micrófono para detectar sonidos, grabar frases y, opcionalmente, reconocer voz. El audio de la monitorización ambiental se procesa en memoria y no se guarda de forma intencionada. Las grabaciones que creas explícitamente, los ajustes y las estadísticas se almacenan en el espacio privado de la aplicación en tu dispositivo.\n\nLos proveedores de reconocimiento de voz y síntesis de voz seleccionados en Android pueden procesar el audio o el texto de las frases de forma local o remota, de acuerdo con sus propias políticas. Parrot Trainer no dispone de un backend operado por el desarrollador, publicidad ni analítica, y no vende tus datos.\n\nPuedes eliminar grabaciones, restablecer los ajustes y las estadísticas, borrar los datos de la aplicación o desinstalarla. Android puede realizar copias de seguridad de algunos ajustes y estadísticas según la configuración de tu dispositivo; las grabaciones de audio de las frases están excluidas de las reglas de copia de seguridad de Parrot Trainer.\n\nPreguntas sobre privacidad: https://github.com/DimonSmart/ParrotTrainer/issues';
}
