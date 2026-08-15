# stt_record

Record audio to a WAV file while streaming speech-to-text transcripts in realtime — using a single microphone capture path on iOS and Android.

The main goal is to avoid “two plugins fighting over the mic” (for example, trying to run a recorder plugin and a speech-to-text plugin at the same time).

## Features

- Realtime transcript stream (partial + final) via a Dart `Stream`.
- Simultaneous WAV recording from the same microphone session.
- `pause()` / `resume()` without finalizing the WAV file (continues writing into the same file).
- Session state stream for interruption handling (`paused` / `resumed`).
- Best-effort normalized microphone amplitude (`0.0..1.0`) via `getAmplitude()`.
- Best-effort supported speech recognition locales via `getLocales()`.

Notes:

- Transcript events contain the **full transcript so far** (accumulated on the native side), not just the latest segment.
- Audio format: PCM16, 16 kHz, mono (`.wav`).

## Supported platforms

- Android (minSdk 24)
- iOS (minimum iOS 13)

Build notes:

- Android module is currently configured with `compileSdk 36` and Java 17. If your build fails with a missing `android-36` platform, install Android SDK Platform 36 (SDK Manager) or adjust `android/build.gradle` in this plugin.

This plugin uses the platform speech recognizers:

- Android: `SpeechRecognizer` (device/service dependent)
- iOS: `SFSpeechRecognizer`

## Installation

Add the dependency as usual:

```bash
flutter pub add stt_record
```

Or in `pubspec.yaml`:

```yaml
dependencies:
  stt_record: ^0.0.2
```

## Dart API (overview)

- Streams
  - `transcripts`: realtime transcript events (`text`, `isFinal`)
  - `sessionStates`: `paused` / `resumed` (interruptions or manual pause/resume)
- Permissions
  - `hasPermission()`
  - `requestPermission()`
- Session
  - `start(localeId, partialResults)`
  - `pause()` / `resume()`
  - `stop()` → returns `audioPath` (finalizes WAV)
  - `cancel()` (best-effort cleanup; may delete the recorded file)
- Utilities
  - `getAmplitude()` → normalized `0.0..1.0` (best-effort)
  - `getLocales()` → locale list (`localeId`, `name`) (best-effort)

## Platform setup

### Android

1) Add microphone permission to your app manifest:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

2) Foreground service behavior

- While recording, the plugin starts a minimal **foreground service** to keep audio capture alive when the app goes to background.
- On Android 12+ you should call `start()` while the app is in the foreground (Android restricts starting foreground services from the background).

3) Notifications (Android 13+)

The foreground service uses a notification (channel id: `stt_record`). If you want it to be visible on Android 13+ (API 33+), you may need:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

and request it at runtime (your app’s responsibility).

4) Speech recognition availability

If `SpeechRecognizer` is not available on the device, `start()` fails with `stt_unavailable`.

5) Audio injection / fallback (important)

- Android 13+ (API 33+): audio injection is supported and is the most reliable mode.
- Android 12–12L (API 31–32): injection is best-effort and may be ignored by some speech engines.
- Android 11 and below (API ≤ 30): injection is not available. The plugin falls back to `RecognitionListener.onBufferReceived`, which is **not guaranteed** to provide audio buffers on all devices/services. In this case, the WAV file may be incomplete or even empty.

### iOS

1) Add usage descriptions to your app `Info.plist`:

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

Example:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record audio.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition to convert speech to text.</string>
```

2) Device notes

- Speech recognition behavior depends on iOS availability and locale support.
- For the most reliable results, test on a real device.

## Usage

```dart
import 'package:stt_record/stt_record.dart';

final stt = SttRecord();

Future<void> run() async {

  // Permissions
  final ok = await stt.requestPermission();
  if (!ok) return;

  // Locales (best-effort)
  final locales = await stt.getLocales();
  // Example: print the first few
  // print(locales.take(5).map((e) => '${e.name} (${e.localeId})').toList());

  // Streams
  final transcriptSub = stt.transcripts.listen((evt) {
    // evt.text is the full transcript so far
    // evt.isFinal indicates a committed final result
  });

  final stateSub = stt.sessionStates.listen((state) {
    // paused/resumed can happen due to interruptions (calls, audio focus)
    // or when your app calls pause()/resume()
  });

  // Start
  await stt.start(localeId: 'vi-VN', partialResults: true);

  // Optional: poll amplitude for a mic level UI
  final amp = await stt.getAmplitude();
  // amp is normalized to 0.0..1.0 (best-effort)

  // Stop (finalizes WAV) and get the file path
  final res = await stt.stop();
  // res.audioPath

  await transcriptSub.cancel();
  await stateSub.cancel();
}
```

### Pause / resume

Pause/resume does not finalize the WAV file:

```dart
await stt.pause();
await stt.resume();
```

### Cancel

`cancel()` is best-effort cleanup and may delete the recorded file:

```dart
await stt.cancel();
```

### Returned WAV path

- Android: the WAV is written to the app cache directory.
- iOS: the WAV is written to the app temporary directory.

These locations may be cleaned by the OS. If you need persistence, copy/move the file to your app’s documents directory.

## Errors & troubleshooting

- `permission_denied`: microphone permission (and on iOS, speech recognition permission) is required.
- `stt_unavailable` (Android): no speech recognition service is available.
- Empty/partial WAV on Android API ≤ 30: this is expected on some devices because audio buffer callbacks are not guaranteed in fallback mode.
- Foreground service start issues (Android 12+): ensure `start()` is called while the app is in the foreground.

## Example

See `example/` for a simple UI that:

- Requests permissions
- Starts/stops recording
- Shows transcript and session state
- Plays recorded WAV files

