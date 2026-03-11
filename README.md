# Asset Shield

Asset Shield is a Flutter plugin for encrypting and loading app assets securely.
It provides a build-time encryption CLI and a runtime decryption API backed by
native libraries (AES‑256‑GCM) with optional native Zstd compression.

## Features

- Encrypt any asset type (images, audio, JSON, models, etc.)
- Native AES‑256‑GCM encryption/decryption on Android/iOS/macOS/Linux/Windows
- Native Zstd compression with multi‑threading
- Simple CLI workflow (`init` + `encrypt`)
- Chunked V3 format for large assets and parallel crypto

Note: Web is not supported.

## Quick Start

### 1) Initialize config

```bash
dart run asset_shield init
```

This generates `shield_config.yaml` in your project root.

### 2) Configure `shield_config.yaml`

```yaml
raw_assets_dir: assets
encrypted_assets_dir: assets/encrypted
config_output: lib/generated/asset_shield_config.dart
compression: zstd
compression_level: 3
chunk_size: 262144
crypto_workers: -1
zstd_workers: -1
extensions:
  - .png
  - .jpg
  - .jpeg
  - .json
  - .mp3
key: "REPLACE_WITH_BASE64_KEY"
emit_key: true
```

Notes:
- `compression: zstd` compresses per‑chunk and keeps the smaller result.
- `chunk_size` controls crypto chunking (bytes).
- `crypto_workers`/`zstd_workers`: `-1` = auto, `0/1` = single-thread.
- `zstd_workers` currently affects compression only (decompression is single-threaded).
- `crypto_workers` affects runtime decrypt parallelism (CLI encrypt is single-threaded).
- Key length must be 32 bytes for AES‑256‑GCM.
- `useNative` must be true (Dart crypto removed).
- Hashed filenames are always used (no plaintext map).
  - This obscures asset filenames in the package, but your source still contains original paths.

### 3) Encrypt assets

```bash
dart run asset_shield encrypt
```

Outputs:
- Encrypted assets: `assets/encrypted/*`
- Config output: `lib/generated/asset_shield_config.dart`

### 4) Register encrypted assets

```yaml
flutter:
  assets:
    - assets/encrypted/
```

### 5) Initialize at runtime

```dart
import 'package:asset_shield/asset_shield.dart';
import 'package:asset_shield/crypto.dart';
import 'generated/asset_shield_config.dart';

void main() {
  final key = ShieldKey.fromBase64(assetShieldKeyBase64);
  Shield.initialize(
    key: key,
    encryptedAssetsDir: assetShieldEncryptedDir,
  );
  runApp(const MyApp());
}
```

### 6) Use encrypted assets

```dart
// Image
ShieldImage('assets/images/logo.png');

// Bytes / JSON
final bytes = await Shield.loadBytes('assets/config.json');
final json = await Shield.loadString('assets/config.json');
```

### 7) Seamless Image.asset support (AssetBundle injection)

```dart
return DefaultAssetBundle(
  bundle: ShieldAssetBundle(),
  child: const MyApp(),
);
```

This makes existing `Image.asset('...')` calls load and decrypt automatically.
Calls that use `rootBundle.load` are not intercepted; prefer `DefaultAssetBundle`
or `Shield.loadBytes` for those.

## API Reference

### Core
- `Shield.initialize({ key, isolateThresholdBytes, useNative, nativeLibraryPath, encryptedAssetsDir, cryptoWorkers, zstdWorkers })`
- `Shield.initializeWithNativeKey({ isolateThresholdBytes, nativeLibraryPath, encryptedAssetsDir, cryptoWorkers, zstdWorkers })`
- `Shield.setNativeKey(keyBytes)`
- `Shield.clearNativeKey()`
- `Shield.loadBytes(assetPath)`
- `Shield.loadString(assetPath)`

### Widgets
- `ShieldImage(assetPath)`
- `ShieldAssetBundle` (AssetBundle injection)

## Developer Guide

### CLI

```bash
dart run asset_shield init
dart run asset_shield encrypt
dart run asset_shield gen-key --length 32
```

### Native Libraries (prebuilt)

- Android: `android/src/main/jniLibs/**`
- iOS: `ios/Frameworks/AssetShieldCrypto.xcframework`
- macOS: `macos/Frameworks/libasset_shield_crypto.dylib` and `macos/Frameworks/AssetShieldCrypto.xcframework`
- Linux: `linux/lib/libasset_shield_crypto.so`
- Windows: `windows/lib/asset_shield_crypto.dll`

### Swift Package Manager (SPM)

- iOS: `ios/Package.swift`
- macOS: `macos/Package.swift`

### Publisher Workflow (multi‑machine build)

Build and commit native binaries before publishing:

**Mac (iOS + macOS)**
```bash
./tool/build_macos.sh
./tool/build_ios.sh
```

**Linux**
```bash
./tool/build_linux.sh
```

**Windows**
```powershell
.\tool\build_windows.ps1
```

**Android (Mac or Linux)**
```bash
ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/<version> ./tool/build_android.sh
```

### Key Management

Two options:

1) **Dart key (default)**  
   Pass the key into `Shield.initialize`.

2) **Native embedded key (obfuscation)**  
   Build native libraries with `ASSET_SHIELD_KEY_BASE64`:

```bash
ASSET_SHIELD_KEY_BASE64=<base64> ./tool/build_macos.sh
ASSET_SHIELD_KEY_BASE64=<base64> ./tool/build_ios.sh
ASSET_SHIELD_KEY_BASE64=<base64> ./tool/build_android.sh
```

You can also set/rotate keys at runtime:
```dart
Shield.setNativeKey(keyBytes);
Shield.clearNativeKey();
```

## License

MIT. See `LICENSE`.
