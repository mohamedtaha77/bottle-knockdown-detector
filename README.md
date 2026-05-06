# 🎯 Bottle Knockdown Detector

A Flutter Android application that uses a custom-trained **YOLOv11s** AI model to automatically detect and score bottle knockdowns from toy-car race videos.

Built as a bonus project for **DSAI 352** — Spring 2026.

---

## 📱 What It Does

1. You pick a video of a toy car driving through a row of bottles.
2. The app processes every frame using on-device AI inference.
3. It detects standing bottles, fallen bottles, and the car.
4. It produces an annotated output video with bounding boxes, labels, car trajectory, and a HUD showing the score.
5. You get a final knock-down percentage score.

---

## 🧠 How It Works

```
📹 Input video
      │
      ▼
[Native Kotlin] Extract frames @ 5fps, resized to 640px
      │
      ▼
[Dart × N frames]
  ├─ Decode JPEG → 320×320 tensor
  ├─ YOLOv11s TFLite inference
  ├─ NMS filter → clean detections
  ├─ Bottle tracker (IoU + distance + colour)
  ├─ Fall detector (2-of-3 sliding window)
  └─ Car tracker + trajectory
      │
      ▼
[Native Kotlin] Draw overlays (Android Canvas) + H.264 encode
      │
      ▼
📊 Score + annotated video
```

---

## 🏗️ Architecture

| Layer | Technology |
|---|---|
| UI | Flutter + Riverpod |
| AI Inference | TFLite Flutter (`tflite_flutter`) |
| Image Processing | Dart `image` package |
| Video I/O | Native Kotlin (MediaCodec + MediaMuxer) |
| Audio | `audioplayers` |
| State Management | `flutter_riverpod` |

### Key Files

```
lib/
├── main.dart
├── models/
│   ├── bottle.dart
│   ├── detection.dart
│   └── processing_result.dart
├── services/
│   ├── detector_service.dart       # TFLite inference + NMS
│   ├── tracker_service.dart        # Multi-object bottle tracking
│   ├── fall_detector_service.dart  # Sliding window fall confirmation
│   ├── car_tracker_service.dart    # Car position + trajectory
│   ├── video_processor_service.dart
│   ├── music_service.dart
│   └── sfx_service.dart
├── screens/
│   ├── home_screen.dart
│   ├── processing_screen.dart
│   └── result_screen.dart
├── providers/
│   └── video_processor_provider.dart
└── utils/
    ├── constants.dart
    ├── extensions.dart
    ├── logger.dart
    └── overlay_renderer.dart
android/app/src/main/kotlin/.../
├── MainActivity.kt
└── VideoChannel.kt    # Native frame extract + annotate+encode
```

---

## 🤖 AI Model

- **Architecture**: YOLOv11s fine-tuned on custom dataset
- **Classes**: `Car` (0), `bottle` (1), `fallen` (2)
- **Export**: TFLite float32 with NMS baked in (`nms=True`)
- **Input**: `[1, 320, 320, 3]` float32
- **Output**: `[1, N, 6]` → `[x1, y1, x2, y2, confidence, class_id]`
- **Inference**: CPU, 4 threads

---

## ⚙️ Assets Setup

Large binary files are **not included** in this repo. Place them manually after cloning:

```
assets/
├── models/
│   └── best_float32.tflite      ← YOLOv11s fine-tuned model
├── audio/
│   ├── music/
│   │   ├── home_bg.mp3
│   │   ├── processing_bg.mp3
│   │   └── results_bg.mp3
│   └── sfx/
│       └── bottle_fallen.wav
└── icon/
    └── app_icon.png             ← 1024×1024 PNG
```

---

## 🚀 Getting Started

```bash
# Install dependencies
flutter pub get

# Generate app icons (after placing app_icon.png)
dart run flutter_launcher_icons

# Run on connected Android device
flutter run

# Or build APK
flutter build apk --debug
adb install -r -t build/app/outputs/flutter-apk/app-debug.apk
```

**Requirements**: Flutter `^3.8.1`, Android API 24+

---

## 📦 Key Dependencies

| Package | Purpose |
|---|---|
| `tflite_flutter` | On-device TFLite inference |
| `image` | JPEG decode + letterbox |
| `flutter_riverpod` | State management |
| `video_player` | Output video playback |
| `file_picker` | Input video selection |
| `gal` | Save to gallery |
| `audioplayers` | Music + SFX |

---

## 📄 License

Academic use — DSAI 352, Imam Abdulrahman Bin Faisal University, Spring 2026.
