# Google Play release checklist

Last reviewed: 23 August 2026.

## Repository readiness

- Package ID: `com.dimonsmart.parrottrainer`.
- `targetSdk` / `compileSdk`: API 36 (Android 16).
- Minimum Android version: API 24 (Android 7.0).
- Release format: Android App Bundle (`.aab`).
- Microphone foreground service type and permissions are declared in the Android manifest.
- Recorded phrase audio is excluded from Android cloud backup and device-transfer backup.
- Upload signing is configured from the local, ignored `android/key.properties` file.

## Local release verification

```shell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

The signed bundle is written to:

`build/app/outputs/bundle/release/app-release.aab`

A Play upload must be signed. Create a separate upload key and configure local
`android/key.properties` as described in [DEVELOPMENT.md](../DEVELOPMENT.md).
Never commit the keystore or passwords. New Google Play apps use Play App
Signing; keep the local key as the upload key.

Before the first upload, also test the release build on a physical Android
device and on a 16 KB page-size emulator/device because the app includes native
Flutter/plugin libraries.

## Store listing assets still required outside the repository

Google Play requires, at minimum:

- a 512 x 512 Play Store icon (32-bit PNG, max 1024 KB);
- a 1024 x 500 feature graphic (JPEG or 24-bit PNG without alpha);
- at least two phone/device screenshots meeting Play's dimensions; four good
  portrait phone screenshots are recommended for this app;
- a support email address;
- a publicly accessible privacy-policy URL.

Listing copy is prepared in [google-play-listing.md](google-play-listing.md).

## Privacy policy publication

The policy source is [privacy-policy.md](privacy-policy.md). A repository file
URL is not sufficient by itself: publish it as a normal public web page. One
simple option is GitHub Pages using the `main` branch `/docs` folder, then use
the resulting public privacy-policy page URL in Play Console.

The developer/entity name shown in Play Console must match the developer/entity
identified in the privacy policy. If the Play listing uses a different legal or
developer name, update the policy before submission.

## Play Console declarations

### App access / ads / accounts

- App access: all functionality is available without login or restricted access.
- Ads: No.
- Accounts: the app does not create user accounts.

Complete the content-rating and target-audience questionnaires according to the
actual intended audience. The app is a general-purpose pet-training utility;
do not opt into child-directed/Families distribution unless that is actually
the intended audience and the app has been reviewed against those policies.

### Data Safety

The app itself has no developer-operated backend, advertising, analytics, or
crash-reporting SDK. Ambient microphone monitoring is processed on-device and
is not intentionally retained. User-created phrase recordings, settings,
statistics, and activity history are stored locally.

Do not blindly answer "no data leaves the device". During voice phrase creation,
the Android speech-recognition provider selected on the device may process audio
locally or remotely. The selected Android TTS engine may likewise process phrase
text locally or remotely. Review the behavior of the providers supported by the
release and answer the Data Safety form conservatively. Google Play's Data
Safety guidance treats purely on-device processing as not collected, while
off-device ephemeral processing still needs to be considered in the form.

### Foreground service declaration: microphone

The manifest declares a `microphone` foreground service for training while the
screen is off. Play Console also requires the foreground-service declaration.
Suggested answers:

**Feature description**

> While a user-started training session is running with background training
> enabled, Parrot Trainer continuously measures microphone input to detect a
> parrot sound and trigger the configured training response. Ambient monitoring
> audio is not intentionally saved. Android shows an ongoing notification while
> this foreground service is active.

**Impact if delayed or interrupted**

> If microphone monitoring is delayed or interrupted while the screen is off,
> Parrot Trainer can miss the bird's sound and therefore cannot trigger the
> expected training response until monitoring resumes.

Record a short Android-device video showing: grant microphone permission, start
training, enable the mode that allows the screen to sleep/background training,
turn the screen off or background the app, show the ongoing notification,
produce a sound that triggers the response, then stop training. Upload the video
where Play Console can access it and provide that link in the declaration.

## First Play Console release

1. Create the app in Play Console using package ID `com.dimonsmart.parrottrainer`.
2. Configure Play App Signing.
3. Complete Store listing and App content forms, including Privacy Policy, Data
   Safety and the microphone foreground-service declaration.
4. Upload the signed `.aab` to Internal testing first and resolve every Play
   pre-launch / App Bundle Explorer warning that applies to the app.
5. Run a real-device smoke test from the Play-delivered internal-test build,
   including microphone permission, recording, speech recognition, TTS,
   background training, notification, schedule, statistics and data reset.
6. If the developer account is a personal account created after 13 November
   2023, run the required closed test with at least 12 opted-in testers
   continuously for at least 14 days, then apply for Production access.
7. Promote the tested release to Production when all Console requirements are
   green.

For every later release, increment `version` / build number in `pubspec.yaml`
before uploading a new bundle.
