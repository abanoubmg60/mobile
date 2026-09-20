# AGENTS.md - Lichess Mobile Guidelines

This document provides guidance for Antigravity agents working on the Lichess Mobile codebase.

## Project Overview

Lichess Mobile is the official Flutter-based mobile application (iOS & Android) for [lichess.org](https://lichess.org).
- **Framework**: Flutter (Flutter 3.47+, Dart 3.13+)
- **State Management**: Riverpod (`AsyncNotifier`, `FutureProvider`, `NotifierProvider`)
- **Data Modeling**: Freezed (`@freezed`) with JSON serialization (`json_serializable`)
- **Immutability**: `fast_immutable_collections` (`IList`, `IMap`, `ISet`)
- **Chess Logic**: `dartchess` & `chessground` (v10+ with `CustomPainter` rendering)
- **Engine**: Stockfish via `multistockfish` package running in an isolate
- **Network**: HTTP (`cronet_http`, `cupertino_http`), WebSockets (`lib/src/network/socket.dart`)
- **Translations**: Generated from `translation/source/mobile.xml` (Never edit `app_*.arb` directly)

---

## Directory & Architecture Structure

```
lib/src/
├── model/          # Business logic & Riverpod state providers
│   ├── account/    # User account data & preferences
│   ├── analysis/   # Analysis board & engine evaluation
│   ├── auth/       # OAuth authentication
│   ├── challenge/  # Game challenges
│   ├── common/     # Shared models, ID types, utilities
│   ├── engine/     # Stockfish integration & evaluation
│   ├── game/       # Live & correspondence game logic
│   ├── puzzle/     # Daily puzzle, Puzzle Storm/Streak
│   ├── settings/   # App settings & local persistence
│   └── ...
├── view/           # UI screens and navigation
│   ├── account/
│   ├── analysis/
│   ├── game/
│   ├── home/
│   ├── play/
│   ├── puzzle/
│   ├── settings/
│   └── ...
├── widgets/        # Reusable UI components & custom widgets
├── network/        # HTTP client, WebSocket, connectivity monitoring
├── utils/          # Formatting, helpers, board math
└── styles/         # Theme, board themes, piece sets, icons
```

---

## Critical Development Rules & Conventions

### 1. Immutability (Strict Requirement)
- All data models must be immutable (all fields `final` or `late final`).
- Use **Freezed** for data classes.
- Use **`fast_immutable_collections`** (`IList`, `IMap`, `ISet`) for collections in public APIs.
- Standard Dart collections (`List`, `Map`) are strictly forbidden in public APIs (allowed only in local method scopes).

### 2. Code Generation
This project relies heavily on `build_runner`.
Always run code generation when modifying `@freezed`, `@JsonSerializable`, or other generated annotations:
```bash
dart run build_runner build --delete-conflicting-outputs
```
*Note*: Never commit generated files (`*.freezed.dart`, `*.g.dart`).

### 3. Dot Shorthand Syntax (Dart 3.10+)
Use dot shorthand syntax (`.foo`) whenever context type inference permits:
```dart
// Enums & switch
Status status = .running;
switch (status) {
  case .running: ...
  case .stopped: ...
}

// Widget properties
MainAxisAlignment: .center,
CrossAxisAlignment: .stretch,
```

### 4. Code Quality & Formatting
- **Analyzer**: Always run `flutter analyze` on touched files.
- **Const constructors**: The analyzer strictly enforces `prefer_const_constructors`. Use `const` wherever possible.
- **Identifiers**: Local variables and functions must NEVER start with `_` (reserved for library/class private members).
- **Formatter**: Run `dart format <file>` before committing.
  - Page width is configured to **100 characters**.
  - Trailing commas dictate list/parameter formatting.
  - Wrap comments to 100 characters.

### 5. Testing Patterns
- **Mock at HTTP layer**: Always override `httpClientFactoryProvider` rather than overriding Riverpod providers directly. This preserves `autoDispose` and `keepAlive()` behavior.
- **Chessground v10+**: Pieces and highlights are rendered via `CustomPainter`. Do NOT use `find.byKey(...)` for pieces or squares. Use helpers in `test/test_helpers.dart` (`getBoardPieces(tester)`, `boardHasPiece(...)`, `boardHasPremove(...)`, `squareOffset(...)`).

### 6. Translations (i18n)
- Never modify `lib/l10n/app_*.arb` or `lib/l10n/messages_*.dart` directly.
- For new features, start with hardcoded English strings.
- Once stable, add strings to `translation/source/mobile.xml` and run `./scripts/gen-translations.sh`.

---

## Android APK Compilation & Build Instructions

### Prerequisites on Windows
- **Flutter SDK**: 3.47.x (matching `pubspec.yaml`)
- **Java JDK**: 21 (`C:\Program Files\Microsoft\jdk-21.0.12.8-hotspot\`)
- **Android SDK**: `C:\Users\Administrator\AppData\Local\Android\Sdk` (API 34 installed)

### Building the APK
```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run code generation
dart run build_runner build --delete-conflicting-outputs

# 3. Build Release APK
flutter build apk --release

# Optional: Split per ABI (creates smaller APKs for arm64-v8a, armeabi-v7a, x86_64)
flutter build apk --release --split-per-abi

# Output location:
# build/app/outputs/flutter-apk/app-release.apk
```
