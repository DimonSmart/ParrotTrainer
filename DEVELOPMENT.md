# Development

Parrot Trainer is a Flutter application for Android.

## Implementation notes

- microphone level is measured in dBFS and the trigger threshold is configurable;
- sound detection uses smoothing, hysteresis, and explicit sound start/end events;
- the training flow is implemented as a state machine with protection against reacting to its own TTS output;
- multiple installed Android TTS voices can be selected;
- training phrases and speech settings are editable;
- settings and lifetime statistics are stored locally;
- training stops safely when the app moves to the background.

## Build and test

```shell
flutter pub get
flutter test
flutter analyze
flutter build apk --release
```

The release APK is created at:

```text
build/app/outputs/flutter-apk/app-release.apk
```
