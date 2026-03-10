import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'crypto/shield_crypto.dart';
import 'crypto/shield_compression.dart';
import 'ffi/shield_ffi.dart';

class ShieldConfig {
  const ShieldConfig({
    required this.key,
    required this.assetMap,
    this.isolateThresholdBytes = 512 * 1024,
    this.useNative = true,
    this.nativeLibraryPath,
  });

  final Uint8List key;
  final Map<String, String> assetMap;
  final int isolateThresholdBytes;
  final bool useNative;
  final String? nativeLibraryPath;
}

class Shield {
  static ShieldConfig? _config;

  static void initialize({
    required Uint8List key,
    required Map<String, String> assetMap,
    int isolateThresholdBytes = 512 * 1024,
    bool? useNative,
    String? nativeLibraryPath,
  }) {
    final useNativeValue = useNative ?? !kIsWeb;
    final keyLength = key.lengthInBytes;
    if (keyLength != 16 &&
        keyLength != 32 &&
        !(useNativeValue && keyLength == 0)) {
      throw ArgumentError('Key length must be 16 or 32 bytes for AES-GCM.');
    }
    if (isolateThresholdBytes <= 0) {
      throw ArgumentError('isolateThresholdBytes must be positive.');
    }
    _config = ShieldConfig(
      key: key,
      assetMap: assetMap,
      isolateThresholdBytes: isolateThresholdBytes,
      useNative: useNativeValue,
      nativeLibraryPath: nativeLibraryPath,
    );
  }

  static bool get isInitialized => _config != null;

  static void initializeWithNativeKey({
    required Map<String, String> assetMap,
    int isolateThresholdBytes = 512 * 1024,
    String? nativeLibraryPath,
  }) {
    initialize(
      key: Uint8List(0),
      assetMap: assetMap,
      isolateThresholdBytes: isolateThresholdBytes,
      useNative: true,
      nativeLibraryPath: nativeLibraryPath,
    );
  }

  static void setNativeKey(Uint8List key) {
    final config = _requireConfig();
    if (!config.useNative) {
      throw StateError('Native key requires useNative=true.');
    }
    ShieldFfi.load(libraryPath: config.nativeLibraryPath).setKey(key);
  }

  static void clearNativeKey() {
    final config = _requireConfig();
    if (!config.useNative) {
      return;
    }
    ShieldFfi.load(libraryPath: config.nativeLibraryPath).clearKey();
  }

  static Future<Uint8List> loadBytes(String assetPath) async {
    final config = _requireConfig();
    final encryptedPath = _resolveEncryptedPath(config.assetMap, assetPath);
    final data = await rootBundle.load(encryptedPath);
    final encrypted = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );

    if (encrypted.lengthInBytes >= config.isolateThresholdBytes) {
      return compute(
        _decryptInIsolate,
        <String, Object?>{
          'data': encrypted,
          'key': config.key,
          'useNative': config.useNative,
          'libraryPath': config.nativeLibraryPath,
        },
      );
    }
    return _decryptLocal(encrypted, config.key, config);
  }

  static Future<String> loadString(
    String assetPath, {
    Encoding encoding = utf8,
  }) async {
    final bytes = await loadBytes(assetPath);
    return encoding.decode(bytes);
  }

  static String resolvePath(String assetPath) {
    final config = _requireConfig();
    return _resolveEncryptedPath(config.assetMap, assetPath);
  }

  static ShieldConfig _requireConfig() {
    final config = _config;
    if (config == null) {
      throw StateError('Shield.initialize must be called before loading assets.');
    }
    return config;
  }

  static String _resolveEncryptedPath(
    Map<String, String> assetMap,
    String assetPath,
  ) {
    final encryptedPath = assetMap[assetPath];
    if (encryptedPath == null || encryptedPath.isEmpty) {
      throw StateError('Encrypted asset not found for: $assetPath');
    }
    return encryptedPath;
  }
}

Uint8List _decryptInIsolate(Map<String, Object?> payload) {
  final encrypted = payload['data'];
  final key = payload['key'];
  if (encrypted is! Uint8List || key is! Uint8List) {
    throw StateError('Invalid isolate payload for decryption.');
  }
  final useNative = payload['useNative'] == true;
  final libraryPath = payload['libraryPath'] as String?;
  final header = ShieldCrypto.parseHeader(encrypted);
  if (header.compressed && header.algorithm != 1) {
    throw const FormatException('Unsupported compression algorithm.');
  }
  if (useNative) {
    try {
      final plain =
          ShieldFfi.load(libraryPath: libraryPath).decrypt(encrypted, key);
      if (header.compressed) {
        final decompressed = ShieldCompression.decompress(
          plain,
          originalLength: header.originalLength,
        );
        if (header.originalLength > 0 &&
            decompressed.lengthInBytes != header.originalLength) {
          throw const FormatException('Decompressed length mismatch.');
        }
        return decompressed;
      }
      return plain;
    } catch (_) {
      if (key.isEmpty) {
        throw StateError('Native decrypt failed and no Dart key available.');
      }
      return ShieldCrypto.decrypt(encrypted, key);
    }
  }
  return ShieldCrypto.decrypt(encrypted, key);
}

Uint8List _decryptLocal(Uint8List encrypted, Uint8List key, ShieldConfig config) {
  final header = ShieldCrypto.parseHeader(encrypted);
  if (header.compressed && header.algorithm != 1) {
    throw const FormatException('Unsupported compression algorithm.');
  }
  if (config.useNative) {
    try {
      final plain = ShieldFfi.load(libraryPath: config.nativeLibraryPath)
          .decrypt(encrypted, key);
      if (header.compressed) {
        final decompressed = ShieldCompression.decompress(
          plain,
          originalLength: header.originalLength,
        );
        if (header.originalLength > 0 &&
            decompressed.lengthInBytes != header.originalLength) {
          throw const FormatException('Decompressed length mismatch.');
        }
        return decompressed;
      }
      return plain;
    } catch (_) {
      if (key.isEmpty) {
        throw StateError('Native decrypt failed and no Dart key available.');
      }
      return ShieldCrypto.decrypt(encrypted, key);
    }
  }
  return ShieldCrypto.decrypt(encrypted, key);
}
