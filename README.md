# PPG Recorder

Offline research tool that records a 30-second fingertip video (rear camera,
torch on), extracts the raw red / green / blue PPG signal **from the saved
video on the device**, and exports it as a labelled CSV + metadata JSON + MP4.
No backend, no network, no accounts.

## Workflow

1. **Setup** – enter a Patient ID (letters, digits, `-`, `_`) and optional notes.
   Free storage is checked (≥ 100 MB).
2. **Recording** – the torch turns on and the live quality light shows
   green / yellow / red (finger coverage, motion, overexposure). Once the
   finger has been steady for ~1 s, auto-exposure/focus are locked and the
   30 s recording starts automatically (haptic cue). If the finger leaves the
   lens for > 0.5 s, the attempt is discarded and restarts. Backgrounding the
   app or an incoming call aborts the attempt; nothing is saved.
3. **Processing** – every frame of the recorded MP4 is decoded natively and
   the centre 64×64 px ROI is averaged per channel.
4. **Results** – waveform (red/green, filtered/raw), quality score and
   summary. **Save & Export** (warns if quality is not "good", but lets the
   researcher decide) or **Discard & Retake**. Saved files can be shared via
   the system share sheet.

## Where files are saved

| Platform | Folder |
|---|---|
| Android | `Android/data/com.samionyx.ppg_recorder_app/files/PPG_Recordings/` (visible over USB, no storage permission needed) |
| iOS | App Documents folder → **Files app › On My iPhone › PPG Recorder** |

The folder is removed when the app is uninstalled — export first.

Each recording produces three files sharing one base name
`ppg_{patientID}_{yyyyMMdd_HHmmss}`:

* **`.csv`** – `frame_index,timestamp_ms,red_channel_value,green_channel_value,blue_channel_value`.
  Raw, unfiltered ROI means (0–255). `timestamp_ms` = video presentation
  time relative to the first frame (µs resolution).
* **`.json`** – patient ID, notes, start time (local with offset + UTC),
  video duration, target & measured fps, total / dropped frames, quality
  score and its components, extraction method, colour conversion, camera
  settings, app version and device model.
* **`.mp4`** – the original recording (no audio).

Saving is atomic: files are written under temporary names and renamed; if
any step fails, nothing partial is left behind.

## Signal methodology (matches Sphygma)

| Step | Source |
|---|---|
| Centre 64×64 px ROI mean per frame, R/G/B | Sphygma realtime controller |
| Finger rules: red ≥ 100, red/(g+b) ≥ 0.6, variance 0.1–8000 | Sphygma realtime controller |
| AE/AF metered at centre and locked after ~1 s of steady finger | Sphygma realtime controller |
| Display/quality filtering: Savitzky-Golay detrend (45) → z-score → Butterworth 4th-order 0.7–3.0 Hz `filtfilt` → Savitzky-Golay (11, 3) | Backend `preprocess_hr_signal` |
| Pulse confidence: Welch peak/mean power in 40–200 bpm, 8 s windows / 2 s stride | Backend `HeartRateService` |
| Stability: step jump > 50 % of mean, std > 80 % of mean | Backend `check_signal_quality` |

The Dart DSP is a direct port of the SciPy routines and is verified against
SciPy output in `test/signal/dsp_scipy_parity_test.dart`.

Differences from Sphygma, deliberately:

* YUV→RGB honours the chroma pixel stride (Sphygma's live conversion ignores
  it, which mixes wrong U/V bytes on most Android phones) and, for decoded
  video, the stream's colour matrix/range (BT.601/709, limited/full).
* Per-frame timestamps come from the video container, not wall-clock time.

Quality score = `100 × (0.40·finger coverage + 0.40·pulse confidence +
0.20·stability) − 20·saturated fraction` → good ≥ 70, fair ≥ 40, poor < 40.

## Architecture

```
lib/
  signal/        Pure Dart, no Flutter: DSP, ROI sampler, finger detector,
                 live monitor, quality analyzer (fully unit-tested)
  data/
    services/    Camera (camera plugin), native video decoder bridge,
                 permissions, share, haptics, app/device info
    repositories/RecordingRepository – all file I/O (pending + saved)
    serializers/ CSV encoder, metadata JSON, file naming
  modules/       GetX controller + binding + screen per page
                 (setup, recording, results)
  core/          Constants (all user-facing strings in app_strings.dart),
                 errors, small utilities and widgets
android/…/VideoSignalDecoder.kt   MediaExtractor + MediaCodec decoder
ios/Runner/AppDelegate.swift      AVAssetReader decoder
```

Controllers depend on service interfaces registered in
`app/initial_binding.dart`, so they can be swapped for fakes in tests.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # on a physical device (camera + torch required)
```

Regenerate the SciPy reference fixture (needs `numpy` and `scipy`):

```bash
python tool/generate_scipy_reference.py
```

Requirements: Android 7.0 (API 24)+, iOS 13+, a rear camera with flash.
On iOS run `pod install` via `flutter build ios` on a Mac; the Podfile
enables only the camera permission for `permission_handler`.

### Tunables

* `lib/core/constants/app_config.dart` – duration, fps, storage minimum,
  finger stability/grace frames.
* `lib/signal/signal_config.dart` – ROI size, finger thresholds, filter
  parameters, quality weights and thresholds.
