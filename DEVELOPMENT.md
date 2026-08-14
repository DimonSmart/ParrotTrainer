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
flutter build appbundle --release
```

The release App Bundle is created at:

```text
build/app/outputs/bundle/release/app-release.aab
```

## Android release signing

Create a separate upload key (never commit it):

```shell
keytool -genkeypair -v -keystore android/parrot-trainer-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Create `android/key.properties` locally:

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=upload
storeFile=parrot-trainer-upload.jks
```

Then run `flutter build appbundle --release`. `key.properties`, `.jks`, and
`.keystore` files are ignored by Git. Without `key.properties` Gradle produces
an unsigned, release-compatible bundle for CI checks.
