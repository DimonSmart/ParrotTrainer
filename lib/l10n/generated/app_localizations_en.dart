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
      'Parrot Trainer uses the microphone for sound detection, phrase recording, and optional speech recognition. Ambient monitoring audio is processed in memory and is not intentionally saved. Recordings you explicitly create, settings, and statistics are stored in app-private storage on your device.\n\nAndroid\'s selected speech-recognition and text-to-speech providers may process audio or phrase text locally or remotely according to their own policies. Parrot Trainer has no developer-operated backend, advertising, or analytics and does not sell your data.\n\nYou can delete recordings, reset settings and statistics, clear the app\'s storage, or uninstall the app. Android may back up some settings and statistics according to your device configuration; recorded phrase audio is excluded from Parrot Trainer\'s Android backup rules.\n\nPrivacy questions: https://github.com/DimonSmart/ParrotTrainer/issues';
}
