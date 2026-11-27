# Agent Instructions & Project Guidelines

> Universal AI agent steering document for **mobai**. Any AI coding assistant (Antigravity, Gemini, Copilot, Cursor, Claude Code, etc.) working on this repository should follow these instructions.

---

## 1. Project Overview
- **Project Name:** `mobai`
- **Type:** Cross-platform Mobile AI Chat & Local LLM Runner (Android & iOS)
- **Dart SDK:** `^3.12.2` (Strict Null Safety)
- **Design System:** Material 3 (`useMaterial3: true`), Typography styled with `google_fonts` (`Inter`), using `material_ui` + Flutter Material widgets.
- **Core Stack & Dependencies ([pubspec.yaml](pubspec.yaml)):**
  - **Inference:** `llamadart` & `llamadart_llama_cpp_flutter` (on-device GGUF execution)
  - **Networking:** `dio` (Hugging Face API & buffered HTTP Range downloads)
  - **Storage & Permissions:** `path_provider`, `file_picker`, `permission_handler`, `shared_preferences`
- **Target Platforms:**
  - **Android:** `minSdk >= 24`, `compileSdk = 37`, Java 17 ([android/app/build.gradle.kts](android/app/build.gradle.kts)), package `com.example.mobai`
  - **iOS:** `UIFileSharingEnabled` & `LSSupportsOpeningDocumentsInPlace` enabled ([ios/Runner/Info.plist](ios/Runner/Info.plist))

---

## 2. Directory & Architecture Structure

```text
lib/
├── main.dart                                # App entrypoint: Storage, ModelManager, Notifications, Chat init + theme
├── models/
│   ├── open_model.dart                      # OpenModel, GgufVariant, GgufPart, SplitShardInfo, HF/cardData parsing
│   ├── downloaded_model.dart                # DownloadedModel metadata + multi-part shard filenames
│   ├── model_filter_criteria.dart           # Size/Params/RAM ranges, creator set, hideNotRecommended, downloadedOnly
│   └── chat_session.dart                    # ChatSession & ChatMessage persistence models
├── services/
│   ├── storage_service.dart                 # Singleton: MobAI/{models,chats}, SAF paths, HF token & host scoping
│   ├── model_catalog_service.dart           # HF API (/api/models + expand[] + blobs=true + README.md) & offline asset
│   ├── model_manager_service.dart           # Singleton: catalog state, lazy enrichment, Range 206/split downloads
│   ├── local_inference_service.dart         # Singleton: llamadart engine, single-model RAM policy, CPU retry fallback
│   ├── chat_session_service.dart            # Singleton: queued per-session JSON writes & inference streaming
│   ├── download_notification_service.dart   # Method/EventChannel bridge, lifecycle detach handler, openUrl, RAM query
│   └── hf_url_parser.dart                   # HF repo/blob/resolve URL normalization & hf:// parsing
├── screens/
│   ├── home_screen.dart                     # Chat list, Drawer (Storage & HF Token), PopScope backgrounding, downloads UI
│   ├── model_selector_screen.dart           # HF catalog, All/My Models scope, Sort/Filter bar, details & link dialogs
│   ├── chat_screen.dart                     # Token streaming, stop generation, missing-model guard, prompt/temp config
│   ├── model_selector_screen_s.dart         # Unused UI draft/scratch screen (not wired into navigation)
│   └── widgets/
│       ├── active_downloads_sheet.dart      # DownloadIndicatorButton + modal queue manager (Pause/Resume/Cancel)
│       ├── model_filter_bottom_sheet.dart   # Filter switches, bidirectional Min/Max inputs, searchable creator list
│       ├── add_custom_model_dialog.dart     # Custom HF/direct URL resolver & local .gguf importer
│       ├── hf_token_dialog.dart             # Hugging Face Bearer token setup/clear dialog
│       └── storage_setup_dialog.dart        # First-launch & Drawer storage folder setup & migration dialog
└── utils/
    └── format_utils.dart                    # formatSizeMb (MB/GB/TB), formatSizeWithParts, formatBytes, dates & counts

android/app/src/main/
├── AndroidManifest.xml                      # Foreground dataSync service, wake lock, notification receiver & perms
└── kotlin/com/example/mobai/
    ├── MainActivity.kt                      # Method/EventChannels ("com.example.mobai/download_notifications"), RAM, openUrl
    ├── DownloadForegroundService.kt         # Persistent notification progress + WakeLock/WifiLock + task-remove pause
    └── DownloadNotificationReceiver.kt      # Notification Pause/Resume/Cancel broadcast handler

ios/Runner/
└── AppDelegate.swift                        # MethodChannel handler for openUrl & getDeviceRamMb

assets/json/
├── supported_models.json                    # Offline fallback model catalog (registered in pubspec.yaml)
└── sample_model.dart                        # Stray reference/sample file (not compiled in lib/)

test/                                        # 11 test suites (56 tests): unit, HttpServer integration, widget tests
```

---

## 3. Essential Commands

### Standard Flutter Workflow
- **Fetch dependencies:** `flutter pub get`
- **Static analysis & linting:** `flutter analyze`
- **Run unit & widget tests:** `flutter test`
- **Run app:** `flutter run`

### Host Environment & Native Build Notes
- **SDK alignment & `--no-pub`:** Ensure the `flutter` binary on `PATH` matches `.dart_tool/package_config.json`. If local symlink permissions restrict `flutter pub get`, run:
  ```powershell
  flutter analyze --no-pub
  flutter test --no-pub
  ```
- **Android Kotlin & Manifest check (PowerShell):**
  ```powershell
  $env:JAVA_HOME = '<path-to-jdk-17>'
  cd android; .\gradlew.bat :app:compileDebugKotlin :app:processDebugMainManifest
  ```

---

## 4. Architecture & Domain Invariants

### Hugging Face API & Size / Description Resolution
- **`expand[]` over `full=true`:** HF `/api/models?filter=gguf&full=true` omits `gguf` metadata (`total`, `totalFileSize`), `cardData`, and `siblings[].size`. Always request explicit `expand[]` params with `ListFormat.multi`, then lazily fetch `/api/models/<repoId>?blobs=true` and `/raw/main/README.md` via `ModelManagerService` for exact variant sizes and descriptions.
- **Sizeless variant cache guard:** Never short-circuit `getVariantsForModel` on cached `model.variants` unless `model.hasExactSizes` is `true` (at least one variant carries `sizeBytes > 0`).
- **Gated models & Token security:** Only send `Authorization: Bearer <hfToken>` when `StorageService.isHuggingFaceHost(url)` is true (`huggingface.co`, `hf.co`, or subdomains). Never send HF tokens to third-party mirrors/hosts.

### Downloads, Persistence & Background Lifecycle
- **On-disk `MobAI/` layout:** `StorageService` manages `<root>/MobAI/{models,chats}` (`normalizeMobaiRoot` prevents `MobAI/MobAI` nesting).
  - `models/models_index.json` tracks completed `.gguf` & split shards (`partFileNames`).
  - `models/downloads_state.json` persists active/paused offsets & split-part progress across restarts (deletion must tolerate concurrent calls via `_cleanupPartFile`).
  - `models/custom_models.json` persists user-added URLs and `local:` imported files.
  - `chats/<sessionId>.json` serializes per-session writes cleanly via `_saveQueues`.
- **Buffered & Resumable Streaming:** Downloads stream with a 1 MB `BytesBuilder` buffer, ~1000 ms progress notifications, and HTTP `Range: bytes=<offset>-` resume (`206` resume, `200` restart fallback, `416` EOF/re-download handling).
- **Split-GGUF Shards (`-00001-of-0000N.gguf`):** `OpenModel.parseSplitShard` groups shards into a single variant, downloading parts sequentially (`1..N`). Only Part 1 (`partIdx == 0`) starts with the `GGUF` magic header (`0x47 0x47 0x55 0x46`); secondary shards are raw tensor chunks. Reject inference/sync on incomplete shard sets or auxiliary weights (`mmproj`, `mtp`, `draft`).
- **Lifecycle rule:** Do **not** pause active downloads on navigation (`PopScope` uses `moveToBackground()` when active downloads exist), search/sort/filter changes, or app backgrounding (`inactive`/`paused`/`hidden`). Only pause/flush on explicit Pause/Cancel actions or process termination (`AppLifecycleState.detached` / Android `onTaskRemoved`).
- **Platform parity note:** Native foreground download notifications (`DownloadForegroundService`) are implemented for Android; both Android (`MainActivity.kt`) and iOS (`AppDelegate.swift`) implement `"openUrl"` and `"getDeviceRamMb"` on channel `"com.example.mobai/download_notifications"`.

### Single-Model Inference Policy
- `LocalInferenceService` keeps **at most one model in RAM** to avoid mobile OOM. Always invoke `onBeforeDeleteModel` / `unloadModel()` before deleting or switching models.
- Always surface phone-RAM warnings (`minRamGb > deviceRamGb || minRamGb > 12`) before downloading heavy desktop-scale models.

---

## 5. Coding Standards & Testing Conventions

- **Linting:** Must satisfy `analysis_options.yaml` (`package:flutter_lints/flutter.yaml`) with zero issues on `flutter analyze`. `analysis_options.yaml` excludes `build/**`, `android/**`, and `ios/**` (only Android & iOS platform targets exist).
- **Documentation:** Keep [README.md](README.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and [AGENTS.md](AGENTS.md) in sync when adding services, platform channels, or dependencies.
- **Null Safety & Widgets:** Avoid force unwraps (`!`) unless strictly guaranteed. Prefer `const` constructors, shallow helpers (avoid duplicating UI or service logic), and guard `BuildContext` across async gaps cleanly.
- **State & Sync:** `ModelManagerService` (`filterCriteria.downloadedOnly`) is the single source of truth synced between the `All` / `My Models` chips and the filter bottom sheet.
- **Testing Hooks:** Use `@visibleForTesting` methods (`StorageService.initForTesting`, `ModelManagerService.configureForTesting`, `ChatSessionService.configureForTesting`) and loopback `HttpServer` mocks instead of live network calls. Note `configureForTesting` disables background catalog enrichment by default (`enableBackgroundEnrichment = false`) so mock server tests remain deterministic unless explicitly enabled.

---

## 6. Agent Guardrails & Rules
1. **Preserve Documentation & Comments:** Do not delete existing comments, docstrings, or architectural notes unless directly replacing outdated logic.
2. **Targeted Diffs:** Make minimal, focused edits. Do not reformat or refactor unrelated files outside the scope of the request.
3. **Verify Before Concluding:** Run `flutter analyze` and `flutter test` (with `--no-pub` if local symlink permissions restrict `pub get`) and verify Android Kotlin/Manifest builds whenever touching native `android/` code.
4. **Asset Integrity:** When adding assets or JSON files, register them in [pubspec.yaml](pubspec.yaml) under `flutter.assets`.
