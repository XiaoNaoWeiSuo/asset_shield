import 'dart:typed_data';

/// Stub FFI for unsupported platforms (e.g. web).
class ShieldFfi {
  ShieldFfi._();

  static ShieldFfi load({String? libraryPath}) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List encrypt(
    Uint8List plain,
    Uint8List key, {
    required int compressionAlgo,
    required int compressionLevel,
    required int chunkSize,
    required Uint8List baseIv,
    required int cryptoWorkers,
    required int zstdWorkers,
  }) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List decrypt(
    Uint8List encrypted,
    Uint8List key, {
    required int cryptoWorkers,
    required int zstdWorkers,
  }) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  void setAssetsBasePath(String path) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List decryptAsset(
    String relPath,
    Uint8List key, {
    required int cryptoWorkers,
    required int zstdWorkers,
  }) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  void encryptFile(
    String inputPath,
    String outputPath,
    Uint8List key, {
    required int compressionAlgo,
    required int compressionLevel,
    required int chunkSize,
    required Uint8List baseIv,
    required int zstdWorkers,
  }) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List compress(Uint8List data, {int level = 3}) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List decompress(Uint8List data, {required int originalLength}) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  void release(Uint8List bytes) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  void setKey(Uint8List key) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  void clearKey() {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }
}
