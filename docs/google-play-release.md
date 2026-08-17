# Google Play release checklist

Last reviewed against Google Play requirements: 17 August 2026.

## 1. Build readiness

The Android package is `com.dimonsmart.parrottrainer` and the app targets API 36.
Before the first upload, treat the package name as permanent.

Run:

```shell
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

The signed bundle is created at:

```text
build/app/outputs/bundle/release/app-release.aab
```

Do not upload the unsigned CI bundle to Play Console.

## 2. Release signing

Create a separate upload key and keep it outside Git:

```shell
keytool -genkeypair -v -keystore android/parrot-trainer-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Create `android/key.properties` locally:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=parrot-trainer-upload.jks
```

Build the AAB again after `key.properties` exists. Keep at least two secure backups of the upload keystore and passwords. Enable Play App Signing when creating the app in Play Console.

## 3. Play Console account prerequisites

Before creating the production release:

- complete developer identity/contact verification;
- for a new personal developer account, complete physical Android device verification if Play Console asks for it;
- if the personal developer account was created after 13 November 2023, plan for a closed test with at least 12 opted-in testers for 14 continuous days before requesting Production access.

Internal Testing can be used before Production access is available.

## 4. Store listing

Use the copy in `google-play-listing.md` as the starting English listing.
Provide at least:

- app name;
- short and full descriptions;
- 512x512 32-bit PNG store icon, no more than 1 MB;
- 1024x500 JPEG or 24-bit PNG feature graphic;
- at least two phone screenshots (PNG/JPEG, 320-3840 px, long side no more than twice the short side);
- support email;
- public Privacy Policy URL.

The launcher icon embedded in the AAB is not a substitute for the 512x512 Play Store icon.

## 5. Privacy policy and Data Safety

The app uses the microphone to detect sounds and lets users create local audio recordings. Settings, statistics, phrases, and recordings are stored locally. The application has no proprietary backend, advertising, analytics, or crash-reporting SDK.

Use `privacy-policy.md` as the policy text. The same policy is available from inside the app. Host the policy at a stable public URL and enter that URL in Play Console.

For Data Safety, inspect the final release AAB and answer from actual runtime behavior. Local-only data is not "collected" by Google Play's definition unless it is transmitted off the device. However, Android's selected speech-recognition provider may process speech off-device. Verify the provider behavior used by the released app before finalizing the declaration; do not claim that audio never leaves the device unless that has been verified.

The app does not create user accounts, so account-deletion requirements do not apply.

## 6. App content declarations

Complete the Play Console App content tasks, including:

- Ads: No;
- App access: all functionality is accessible without an account;
- Content rating questionnaire;
- Target audience and content;
- Data Safety;
- Privacy Policy;
- Foreground service declaration for the microphone service.

### Foreground service declaration

The app declares `microphone` foreground-service usage so a user-started training session can continue listening while the screen is off. In Play Console, describe this as a core, user-initiated training feature that remains perceptible through the ongoing notification and can be stopped from the app.

Google Play requires a demonstration video for each declared foreground-service type. Record a short video that shows:

1. opening Parrot Trainer;
2. granting microphone permission;
3. starting training and enabling background/screen-off operation;
4. the persistent foreground-service notification;
5. the app continuing the training session after leaving the foreground or turning the screen off;
6. returning to the app and stopping the session.

Upload the video somewhere accessible to reviewers and provide its link in the foreground-service declaration.

## 7. First release path

Recommended order:

1. Create the app in Play Console using package `com.dimonsmart.parrottrainer`.
2. Enable Play App Signing.
3. Complete Store listing and App content forms.
4. Build a locally signed `app-release.aab`.
5. Upload it to Internal Testing first and install it from Google Play on a physical device.
6. Verify microphone permission, TTS, phrase recording, speech recognition, screen-off/background training, notification behavior, and data deletion.
7. If the account is subject to the new-personal-account requirement, run the required Closed Test and request Production access afterward.
8. Create the Production release and submit it for review.

## 8. Before every update

- increase `version` / build number in `pubspec.yaml`;
- rerun analyze, tests, and signed AAB build;
- review permissions and Data Safety whenever dependencies or behavior change;
- keep the Privacy Policy and store listing consistent with the released application.
