import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../ffi/shield_ffi.dart';

/// Native AES‑256‑GCM encryption/decryption with V3 chunked header.
class ShieldCrypto {
  static const List<int> _magic = <int>[0x41, 0x53, 0x53, 0x54];
  static const int _version4 = 4;
  static const int _algoNone = 0;
  static const int _algoZstd = 1;
  static const int _ivLength = 12;

  /// Encrypts bytes with AES‑256‑GCM and optional compression.
  static Uint8List encrypt(
    Uint8List plainBytes,
    Uint8List keyBytes, {
    bool compress = true,
    int compressionLevel = 3,
    int chunkSize = 256 * 1024,
    int cryptoWorkers = -1,
    int zstdWorkers = -1,
  }) {
    _validateKeyLength(keyBytes, allowEmpty: false);
    if (chunkSize <= 0) {
      throw ArgumentError('chunkSize must be positive.');
    }

    final algo = compress ? _algoZstd : _algoNone;
    final baseIv = _randomBytes(_ivLength);
    for (var i = 8; i < _ivLength; i++) {
      baseIv[i] = 0;
    }

    final workers = _normalizeWorkers(cryptoWorkers);
    final zstd = _normalizeWorkers(zstdWorkers);

    return ShieldFfi.load().encrypt(
      plainBytes,
      keyBytes,
      compressionAlgo: algo,
      compressionLevel: compressionLevel,
      chunkSize: chunkSize,
      baseIv: baseIv,
      cryptoWorkers: workers,
      zstdWorkers: zstd,
    );
  }

  /// Decrypts bytes produced by [encrypt].
  static Uint8List decrypt(
    Uint8List encryptedBytes,
    Uint8List keyBytes, {
    int cryptoWorkers = -1,
    int zstdWorkers = -1,
  }) {
    _validateKeyLength(keyBytes, allowEmpty: true);
    final workers = _normalizeWorkers(cryptoWorkers);
    final zstd = _normalizeWorkers(zstdWorkers);
    return ShieldFfi.load().decrypt(
      encryptedBytes,
      keyBytes,
      cryptoWorkers: workers,
      zstdWorkers: zstd,
    );
  }

  /// Parses the encrypted asset header (V3 only).
  static ShieldHeader parseHeader(Uint8List encryptedBytes) {
    if (encryptedBytes.lengthInBytes < 28) {
      throw const FormatException('Encrypted asset is too short.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (encryptedBytes[i] != _magic[i]) {
        throw const FormatException('Invalid asset header.');
      }
    }

    final version = encryptedBytes[4];
    if (version != _version4) {
      throw FormatException('Unsupported asset version: $version.');
    }

    final flags = encryptedBytes[5];
    final algo = encryptedBytes[6];
    final ivLength = encryptedBytes[7];
    if (ivLength != _ivLength) {
      throw const FormatException('Invalid IV length.');
    }

    final chunkSize = _readUint32Le(encryptedBytes, 8);
    final originalLength = _readUint32Le(encryptedBytes, 12);
    final iv = Uint8List.sublistView(encryptedBytes, 16, 16 + _ivLength);

    return ShieldHeader(
      version: version,
      compressed: (flags & 0x01) != 0,
      algorithm: algo,
      chunkSize: chunkSize,
      originalLength: originalLength,
      baseIv: iv,
    );
  }

  static void _validateKeyLength(Uint8List keyBytes, {required bool allowEmpty}) {
    final length = keyBytes.lengthInBytes;
    if (allowEmpty && length == 0) {
      return;
    }
    if (length != 32) {
      throw ArgumentError('Key length must be 32 bytes for AES-256-GCM.');
    }
  }

  static int _normalizeWorkers(int value) {
    if (value < 0) {
      return Platform.numberOfProcessors;
    }
    if (value == 0) {
      return 1;
    }
    return value < 1 ? 1 : value;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  static int _readUint32Le(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }
}

/// Parsed header for an encrypted asset payload.
class ShieldHeader {
  ShieldHeader({
    required this.version,
    required this.compressed,
    required this.algorithm,
    required this.chunkSize,
    required this.originalLength,
    required this.baseIv,
  });

  final int version;
  final bool compressed;
  final int algorithm;
  final int chunkSize;
  final int originalLength;
  final Uint8List baseIv;
}
