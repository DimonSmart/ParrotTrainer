enum AppLanguage {
  english('en'),
  russian('ru'),
  spanish('es');

  const AppLanguage(this.code);

  final String code;

  static AppLanguage resolve(String? languageCode) =>
      switch (languageCode?.toLowerCase()) {
        'ru' => AppLanguage.russian,
        'es' => AppLanguage.spanish,
        _ => AppLanguage.english,
      };
}
