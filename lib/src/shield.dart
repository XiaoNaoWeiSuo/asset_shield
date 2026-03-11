import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'crypto/shield_hash.dart';
import 'ffi/shield_ffi.dart';

/// Runtime configuration for asset decryption.
class ShieldConfig {
  const ShieldConfig({
    required this.key,
    this.isolateThresholdBytes = 512 * 1024,
    this.useNative = true,
    this.nativeLibraryPath,
    this.encryptedAssetsDir = 'assets/encrypted',
    this.pathResolver,
    this.cryptoWorkers = 1,
    this.zstdWorkers = 1,
    this.useNativeAssetRead = true,
  });

  final Uint8List key;
  final int isolateThresholdBytes;
  final bool useNative;
  final String? nativeLibraryPath;
  final String encryptedAssetsDir;
  final String Function(String assetPath)? pathResolver;
  final int cryptoWorkers;
  final int zstdWorkers;
  final bool useNativeAssetRead;
}

/// Helpers for resolving encrypted asset paths.
class ShieldPathResolver {
  static String hash(String assetPath, {required String encryptedAssetsDir}) {
    final hash = ShieldHash.sha256Hex(assetPath);
    return '$encryptedAssetsDir/$hash.dat';
  }
}

/// Asset Shield runtime API.
class Shield {
  static ShieldConfig? _config;

  /// Initializes the runtime with a Dart key and asset map.
  ///
  /// Use [useNative] to enable native decryption (default on non‑web).
  static void initialize({
    required Uint8List key,
    int isolateThresholdBytes = 512 * 1024,
    bool? useNative,
    String? nativeLibraryPath,
    String encryptedAssetsDir = 'assets/encrypted',
    String Function(String assetPath)? pathResolver,
    int cryptoWorkers = -1,
    int zstdWorkers = -1,
    bool useNativeAssetRead = true,
  }) {
    final useNativeValue = useNative ?? true;
    if (!useNativeValue) {
      throw ArgumentError('Dart crypto has been removed; useNative must be true.');
    }
    final keyLength = key.lengthInBytes;
    if (keyLength != 32 && !(useNativeValue && keyLength == 0)) {
      throw ArgumentError('Key length must be 32 bytes for AES-256-GCM.');
    }
    if (isolateThresholdBytes <= 0) {
      throw ArgumentError('isolateThresholdBytes must be positive.');
    }
    _config = ShieldConfig(
      key: key,
      isolateThresholdBytes: isolateThresholdBytes,
      useNative: useNativeValue,
      nativeLibraryPath: nativeLibraryPath,
      encryptedAssetsDir: encryptedAssetsDir,
      pathResolver: pathResolver,
      cryptoWorkers: _normalizeWorkers(cryptoWorkers),
      zstdWorkers: _normalizeWorkers(zstdWorkers),
      useNativeAssetRead: useNativeAssetRead,
    );

    if (useNativeAssetRead) {
      _tryInitDesktopAssetsBasePath(_config!);
    }
  }

  /// Whether [initialize] has been called.
  static bool get isInitialized => _config != null;

  /// Initializes using a key stored on the native side.
  ///
  /// Useful when the key is embedded or provisioned at runtime.
  static void initializeWithNativeKey({
    int isolateThresholdBytes = 512 * 1024,
    String? nativeLibraryPath,
    String encryptedAssetsDir = 'assets/encrypted',
    String Function(String assetPath)? pathResolver,
    int cryptoWorkers = -1,
    int zstdWorkers = -1,
    bool useNativeAssetRead = true,
  }) {
    initialize(
      key: Uint8List(0),
      isolateThresholdBytes: isolateThresholdBytes,
      useNative: true,
      nativeLibraryPath: nativeLibraryPath,
      encryptedAssetsDir: encryptedAssetsDir,
      pathResolver: pathResolver,
      cryptoWorkers: cryptoWorkers,
      zstdWorkers: zstdWorkers,
      useNativeAssetRead: useNativeAssetRead,
    );
  }

  /// Sets or rotates the native key at runtime.
  static void setNativeKey(Uint8List key) {
    final config = _requireConfig();
    if (!config.useNative) {
      throw StateError('Native key requires useNative=true.');
    }
    ShieldFfi.load(libraryPath: config.nativeLibraryPath).setKey(key);
  }

  /// Clears the native key from memory.
  static void clearNativeKey() {
    final config = _requireConfig();
    if (!config.useNative) {
      return;
    }
    ShieldFfi.load(libraryPath: config.nativeLibraryPath).clearKey();
  }

  /// Loads and decrypts an asset as raw bytes.
  static Future<Uint8List> loadBytes(String assetPath) async {
    final config = _requireConfig();
    final encryptedPath = _resolveEncryptedPath(config, assetPath);
    if (config.useNativeAssetRead) {
      try {
        return ShieldFfi.load(libraryPath: config.nativeLibraryPath).decryptAsset(
          encryptedPath,
          config.key,
          cryptoWorkers: config.cryptoWorkers,
          zstdWorkers: config.zstdWorkers,
        );
      } catch (_) {
        // Fallback to AssetBundle path if native asset read isn't initialized.
      }
    }

    final data = await rootBundle.load(encryptedPath);
    final encrypted = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return _decryptLocal(encrypted, config.key, config);
  }

  /// Loads and decrypts an asset as a string.
  static Future<String> loadString(
    String assetPath, {
    Encoding encoding = utf8,
  }) async {
    final bytes = await loadBytes(assetPath);
    return encoding.decode(bytes);
  }

  /// Resolves the encrypted asset path from the map.
  static String resolvePath(String assetPath) {
    final config = _requireConfig();
    return _resolveEncryptedPath(config, assetPath);
  }

  /// Returns the encrypted asset path if mapped, otherwise null.
  static String? resolvePathOrNull(String assetPath) {
    final config = _config;
    if (config == null) return null;
    return _resolveEncryptedPathOrNull(config, assetPath);
  }

  /// Decrypts an encrypted asset payload using the current configuration.
  static Uint8List decryptBytes(Uint8List encryptedBytes) {
    final config = _requireConfig();
    return _decryptLocal(encryptedBytes, config.key, config);
  }

  static ShieldConfig _requireConfig() {
    final config = _config;
    if (config == null) {
      throw StateError('Shield.initialize must be called before loading assets.');
    }
    return config;
  }

  static String _resolveEncryptedPath(ShieldConfig config, String assetPath) {
    final path = _resolveEncryptedPathOrNull(config, assetPath);
    if (path == null || path.isEmpty) {
      throw StateError('Encrypted asset not found for: $assetPath');
    }
    return path;
  }

  static String? _resolveEncryptedPathOrNull(
    ShieldConfig config,
    String assetPath,
  ) {
    if (config.pathResolver != null) {
      return config.pathResolver!(assetPath);
    }
    return ShieldPathResolver.hash(
      assetPath,
      encryptedAssetsDir: config.encryptedAssetsDir,
    );
  }
}

Uint8List _decryptLocal(Uint8List encrypted, Uint8List key, ShieldConfig config) {
  if (config.useNative) {
    return ShieldFfi.load(libraryPath: config.nativeLibraryPath).decrypt(
      encrypted,
      key,
      cryptoWorkers: config.cryptoWorkers,
      zstdWorkers: config.zstdWorkers,
    );
  }
  throw StateError('Dart crypto has been removed; useNative must be true.');
}

int _normalizeWorkers(int value) {
  if (value < 0) {
    return Platform.numberOfProcessors;
  }
  if (value == 0) return 1;
  return value < 1 ? 1 : value;
}

void _tryInitDesktopAssetsBasePath(ShieldConfig config) {
  // iOS/Android are initialized via platform plugins.
  if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) return;

  // Windows/Linux embed flutter_assets under <exe_dir>/data/flutter_assets.
  if (Platform.isWindows || Platform.isLinux) {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final base = p.join(exeDir, 'data', 'flutter_assets');
    if (Directory(base).existsSync()) {
      ShieldFfi.load(libraryPath: config.nativeLibraryPath).setAssetsBasePath(base);
    }
  }
}
