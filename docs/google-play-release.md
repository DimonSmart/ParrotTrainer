# Google Play release checklist

## Build

```shell
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

The bundle is at `build/app/outputs/bundle/release/app-release.aab`.

## Signing

Create a separate upload key and configure local `android/key.properties` as
described in [DEVELOPMENT.md](../DEVELOPMENT.md). Keep the keystore and all
passwords outside Git. Enable Play App Signing when creating the app.

## Play Console

- Create the application and enable Play App Signing.
- Upload the AAB to Internal Testing first.
- Add the name, short and full descriptions, 512x512 icon, 1024x500 feature
  graphic, screenshots, support email, and Privacy Policy URL.
- Declare Ads: No; complete content rating, target audience, app access, Data
  Safety, Closed Testing, and Production sections.
- New personal developer accounts may need a Closed Testing period before
  Production is available.

## Data Safety notes

The app uses the microphone and lets users create local audio recordings.
Settings and statistics are local. It has no proprietary backend, advertising,
analytics, or crash-reporting SDK. Android's selected speech-recognition
provider may process audio; review that provider's behavior and policy manually
when answering Console questions. Do not infer provider-specific answers from
this document.
