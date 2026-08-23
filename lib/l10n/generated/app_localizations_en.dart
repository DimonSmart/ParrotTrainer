// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Parrot Trainer';

  @override
  String get about => 'About';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get aboutDescription =>
      'A training companion that repeats phrases in response to sounds and during quiet periods.';

  @override
  String get resetSettings => 'Reset settings';

  @override
  String get resetStatistics => 'Reset statistics';

  @override
  String get privacyTitle => 'Privacy Policy';

  @override
  String get privacyBody =>
      'Parrot Trainer uses the microphone to detect sounds and lets you record training phrases. Recordings, settings, and statistics are stored locally on your device.\n\nAndroid\'s selected speech-recognition provider may process audio according to its own policy. Parrot Trainer has no backend and does not send recordings to its own server.\n\nThe app shows no ads and does not sell your data.';
}
