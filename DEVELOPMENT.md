# Development

Parrot Trainer is a Flutter application for Android.

## Implementation notes

- microphone level is measured in dBFS and the trigger threshold is configurable;
- sound detection uses smoothing, hysteresis, and explicit sound start/end events;
- the training flow is implemented as a state machine with protection against reacting to its own TTS output;
- multiple installed Android TTS voices can be selected;
- training phrases and speech settings are editable;
- settings and lifetime statistics are stored locally;
- training can continue safely in the background with the screen off when the owner enables that option; otherwise it stops when the app moves to the background.

## Build and test

```shell
flutter clean
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

Create a separate upload key once (never commit it):

```shell
keytool -genkeypair -v -keystore android/parrot-trainer-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Copy the committed template and replace the placeholder passwords:

### PowerShell

```powershell
Copy-Item android/key.properties.example android/key.properties
```

### macOS / Linux

```shell
cp android/key.properties.example android/key.properties
```

The resulting local file should contain:

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=upload
storeFile=parrot-trainer-upload.jks
```

`storeFile` is resolved relative to the `android` project directory, so the
configuration above points to `android/parrot-trainer-upload.jks`.

Then run:

```shell
flutter build appbundle --release
```

`android/key.properties`, `.jks`, and `.keystore` files are ignored by Git.
Without `key.properties`, Gradle can build an unsigned release-compatible bundle
for CI verification, but that bundle cannot be uploaded as a production release
to Google Play.

Keep a secure backup of the upload keystore and its passwords outside the
repository. Do not ask an automated coding agent to commit, print, or upload
those secrets.

See [docs/google-play-release.md](docs/google-play-release.md) for the complete
Google Play release checklist.
