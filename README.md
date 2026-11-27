# MobAI

**MobAI** is a cross-platform offline AI chat and local GGUF model runner built with Flutter for **Android** and **iOS**. Discover and filter GGUF models directly from Hugging Face, download quantized single-file or split-shard weights reliably in the background, and run private on-device LLM inference powered by [`llamadart`](https://pub.dev/packages/llamadart).

---

## Features

- **On-Device GGUF Inference (`llamadart`)**
  - Runs quantized GGUF models locally with real-time token streaming and cooperative generation cancellation.
  - Enforces a **single-model-in-RAM policy** to avoid mobile out-of-memory crashes and automatically retries with CPU fallback (`contextSize: 1024`, `gpuLayers: 0`) if hardware-accelerated context initialization fails.
  - Persists multi-turn chat sessions (`chats/<sessionId>.json`) along with per-chat **System Prompt** and **Temperature** settings.
  - Rejects incomplete split shards and non-standalone auxiliary weights (`mmproj`, `mtp`, `draft`).

- **Hugging Face Catalog, Search & Full Details**
  - Queries Hugging Face text-generation GGUF repositories with `expand[]` metadata (`gguf`, `safetensors`, `cardData`, `siblings`), RFC 5988 `Link` cursor pagination, and background `?blobs=true` + `README.md` enrichment.
  - Sort by **Popular**, **Latest**, **Smallest/Largest size**, or **Smallest/Largest params**.
  - Tap any model description to view a full specs & cleaned Hugging Face model card popup; tap the link icon for **Open** / **Copy** actions on both Repository and Download URLs (with a download warning on direct `.gguf` links).
  - Inspect available quantizations per repository (`_showVariantPickerSheet`) and warn before downloading desktop-scale models that exceed safe mobile RAM.

- **Advanced Filtering**
  - Switch cleanly between **All** and **My Models** (synced bidirectionally with the **Downloaded only** switch in the filter sheet).
  - Toggle **Hide "Not Recommended" models** based on actual device RAM (`minRamGb > deviceRamGb || minRamGb > 12`).
  - Adjust **Download Size (`GB`)**, **Parameters (`B`)**, and **Minimum RAM (`GB`)** using either sliders or bidirectional **Min / Max** numeric text fields.
  - Filter by **Publishers & Creators** using a searchable checkbox list with model counts.

- **Resumable, Split-GGUF & Background Downloads**
  - Buffered streaming (`1 MB` write buffer, `~1 s` progress notification updates) with HTTP `Range` (`206` / `416`) pause and resume persisted to `models/downloads_state.json`.
  - Sequential multi-part shard downloads (`...-00001-of-0000N.gguf` .. `-NNNNN-of-NNNNN.gguf`) with combined size tracking and completeness verification.
  - **Android foreground service (`DownloadForegroundService`):** Downloads keep running across navigation, filter/search changes, and app backgrounding with persistent notification bar **Pause / Resume / Cancel** actions and an in-app AppBar downloads manager sheet.
  - Optional Hugging Face Bearer token support (`hf_...`) for gated repositories, scoped strictly to Hugging Face hosts.

- **Configurable `MobAI/` Storage & Custom Models**
  - Stores models and chats cleanly inside `<root>/MobAI/{models,chats}` (with folder migration on change and automatic scanning of externally placed `.gguf` files).
  - Import models from Hugging Face links (`repo`, `/blob/`, `/resolve/`, `hf://`), direct `.gguf` URLs, or local device `.gguf` files (validated via the 4-byte `GGUF` magic header).

---

## Supported Platforms

MobAI targets **mobile platforms only**:

| Platform | Requirements | Native Capabilities |
| :--- | :--- | :--- |
| **Android** | `minSdk >= 24`, `compileSdk 37`, Java 17 | Foreground `dataSync` download service, persistent notification actions (`Pause`/`Resume`/`Cancel`), wake/Wi-Fi locks, physical RAM query, browser URL launch, SAF external storage support |
| **iOS** | Xcode / iOS SDK | `UIFileSharingEnabled` & `LSSupportsOpeningDocumentsInPlace` (`Info.plist`), physical RAM query (`getDeviceRamMb`), browser URL launch (`openUrl`) |

> **Note:** Native background download notifications (`DownloadForegroundService`) are implemented for Android. On iOS, active downloads run while the app session stays active.

---

## Project Structure

```text
├── .github/workflows/               # GitHub Actions CI/artifact build on merge to master
├── android/                         # Android Kotlin app, foreground service, manifest & Gradle config
├── ios/                             # iOS Swift runner, Info.plist & Xcode project
├── assets/
│   ├── icons/mobai-icon.png         # App launcher icon asset
│   └── json/supported_models.json   # Offline fallback model catalog
├── docs/
│   └── ARCHITECTURE.md              # Detailed technical architecture & invariants
├── lib/
│   ├── main.dart                    # Service initialization & Material 3 entry point
│   ├── models/                      # OpenModel, GgufVariant/Part, DownloadedModel, FilterCriteria, ChatSession
│   ├── screens/                     # Home, Model Catalog, Chat screens & modal sheets/dialogs
│   ├── services/                    # Storage, HF Catalog, ModelManager, LocalInference, ChatSession, Notifications, HfUrlParser
│   └── utils/                       # Size (MB/GB/TB), compact count & date formatting helpers
├── test/                            # 11 automated test suites (56 unit, HttpServer & widget tests)
├── AGENTS.md                        # AI coding assistant guide & project guardrails
└── pubspec.yaml                     # Flutter dependencies & asset manifest
```

For a deep dive into service boundaries, Hugging Face API behavior, download state persistence, and platform channels, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Getting Started

### Prerequisites
- **Flutter SDK** (`Dart ^3.12.2`)
- **Android:** Android Studio / Android SDK (`compileSdk 37`) & JDK 17
- **iOS:** macOS with Xcode and CocoaPods

### Setup & Run

1. **Install dependencies:**
   ```bash
   flutter pub get
   ```
2. **Verify static analysis and tests:**
   ```bash
   flutter analyze
   flutter test
   ```
3. **Run on an Android emulator/device or iOS simulator/device:**
   ```bash
   flutter run
   ```

> **Developer Tip:** If symlink permissions restrict `flutter pub get` on a local machine setup (when dependencies are already resolved in `.dart_tool/package_config.json`), pass `--no-pub` to `flutter analyze --no-pub` and `flutter test --no-pub`. Ensure the `flutter` executable on your `PATH` matches `.dart_tool/package_config.json`.

### Android Native Build Verification

From the `android/` directory (with `JAVA_HOME` pointing to JDK 17 / Android Studio JBR):
```powershell
$env:JAVA_HOME = '<path-to-jdk-17>'
cd android
.\gradlew.bat :app:compileDebugKotlin :app:processDebugMainManifest
```

### GitHub Actions Build & Release Pipeline

Merging or pushing to `master` triggers [.github/workflows/build-master-apk.yml](.github/workflows/build-master-apk.yml):
1. Computes the next semantic version and build number (`X.Y.Z+<prev+1>`) from Conventional Commits since the latest `v*` Git tag (`!:` / `BREAKING CHANGE:` → **major**, `feat:` → **minor**, `fix:`/other → **patch**; bootstrapping from `pubspec.yaml` on the first release).
2. Runs `flutter analyze` and `flutter test` first.
3. Updates `version:` in [pubspec.yaml](pubspec.yaml), commits (`[skip ci]`) directly to `master`, builds `app-release.apk`, and publishes a **GitHub Release** (`vX.Y.Z`) with auto-generated release notes (preserving all historical releases while keeping `releases/latest/download/app-release.apk` pointed to the newest release) plus a backup Actions artifact. *(Pull `master` into feature/develop branches periodically so local `pubspec.yaml` stays in sync.)*

---

## On-Disk Storage & Privacy

- **Default directory:** `<AppDocuments>/MobAI/` (configurable via the Drawer **Storage location** dialog, with optional migration of existing models and chats).
  - `MobAI/models/models_index.json` — Completed single and split-shard `.gguf` inventory.
  - `MobAI/models/downloads_state.json` — Active/paused `.part` byte offsets and multi-part state across restarts.
  - `MobAI/models/custom_models.json` — Custom Hugging Face / direct URL model definitions.
  - `MobAI/chats/<sessionId>.json` — Persisted chat histories and generation settings.
- **Hugging Face Tokens:** Saved locally in `SharedPreferences` and attached as `Authorization: Bearer <token>` **only** when communicating with verified Hugging Face hosts (`huggingface.co`, `hf.co`, or subdomains).
- **Local Inference:** All prompts, chat histories, and GGUF weights execute strictly on-device with no third-party telemetry or remote inference calls.
