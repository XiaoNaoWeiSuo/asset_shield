## 0.0.4

- Remove asset map usage; hashed filenames only
- Generate runtime config file (no plaintext path map)

## 0.0.3

- Add Swift Package Manager (SPM) support for iOS/macOS
- Add ShieldAssetBundle for seamless DefaultAssetBundle injection
- Add hash-based asset path strategy (no plaintext map)

## 0.0.2

- Add native Zstd compression (no Dart dependency)
- Improve CLI and publishing metadata
- Add web stub and public API documentation

## 0.0.1

- Initial release
- Native AES‑256‑GCM decryption across Android/iOS/macOS/Linux/Windows
- Native Zstd compression support
- CLI workflow (`init`, `encrypt`, `gen-key`)
