import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart'
    show AEADParameters, InvalidCipherTextException, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

import 'shield_compression.dart';

class ShieldCrypto {
  static const List<int> _magic = <int>[0x41, 0x53, 0x53, 0x54];
  static const int _version1 = 1;
  static const int _version2 = 2;
  static const int _algoNone = 0;
  static const int _algoZstd = 1;
  static const int _ivLength = 12;
  static const int _tagLengthBytes = 16;

  static Uint8List encrypt(
    Uint8List plainBytes,
    Uint8List keyBytes, {
    bool compress = true,
    int compressionLevel = 3,
  }) {
    _validateKeyLength(keyBytes);
    final originalLength = plainBytes.lengthInBytes;
    var payload = plainBytes;
    var compressed = false;
    if (compress && originalLength > 0) {
      final compressedBytes =
          ShieldCompression.compress(plainBytes, level: compressionLevel);
      if (compressedBytes.lengthInBytes < originalLength) {
        payload = compressedBytes;
        compressed = true;
      }
    }

    final iv = _randomBytes(_ivLength);
    final cipher = _initCipher(true, keyBytes, iv);
    final encrypted = cipher.process(payload);

    final output = BytesBuilder(copy: false);
    output.add(_magic);
    output.add(<int>[
      _version2,
      compressed ? 0x01 : 0x00,
      compressed ? _algoZstd : _algoNone,
      _ivLength,
    ]);
    output.add(_uint32le(originalLength));
    output.add(iv);
    output.add(encrypted);
    return output.toBytes();
  }

  static Uint8List decrypt(Uint8List encryptedBytes, Uint8List keyBytes) {
    _validateKeyLength(keyBytes);
    final header = _parseHeader(encryptedBytes);
    if (header.version == _version1) {
      return _decryptV1(encryptedBytes, keyBytes);
    }

    if (header.compressed && header.algorithm != _algoZstd) {
      throw const FormatException('Unsupported compression algorithm.');
    }

    final cipher = _initCipher(false, keyBytes, header.iv);
    try {
      final plain = cipher.process(header.cipherText);
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
    } on InvalidCipherTextException catch (error) {
      throw StateError('Failed to decrypt asset: ${error.message}');
    }
  }

  static ShieldHeader parseHeader(Uint8List encryptedBytes) {
    return _parseHeader(encryptedBytes);
  }

  static Uint8List _decryptV1(Uint8List encryptedBytes, Uint8List keyBytes) {
    if (encryptedBytes.lengthInBytes < _magic.length + 2 + _ivLength + 1) {
      throw const FormatException('Encrypted asset is too short.');
    }

    for (var i = 0; i < _magic.length; i++) {
      if (encryptedBytes[i] != _magic[i]) {
        throw const FormatException('Invalid asset header.');
      }
    }

    final version = encryptedBytes[_magic.length];
    if (version != _version1) {
      throw FormatException('Unsupported asset version: $version.');
    }

    final ivLength = encryptedBytes[_magic.length + 1];
    if (ivLength <= 0 || encryptedBytes.lengthInBytes < _magic.length + 2 + ivLength + 1) {
      throw const FormatException('Invalid IV length.');
    }

    final ivStart = _magic.length + 2;
    final ivEnd = ivStart + ivLength;
    final iv = Uint8List.sublistView(encryptedBytes, ivStart, ivEnd);
    final cipherText = Uint8List.sublistView(encryptedBytes, ivEnd);

    final cipher = _initCipher(false, keyBytes, iv);
    try {
      return cipher.process(cipherText);
    } on InvalidCipherTextException catch (error) {
      throw StateError('Failed to decrypt asset: ${error.message}');
    }
  }

  static void _validateKeyLength(Uint8List keyBytes) {
    final length = keyBytes.lengthInBytes;
    if (length != 32) {
      throw ArgumentError(
        'Key length must be 32 bytes for AES-256-GCM.',
      );
    }
  }

  static GCMBlockCipher _initCipher(bool forEncryption, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      _tagLengthBytes * 8,
      iv,
      Uint8List(0),
    );
    cipher.init(forEncryption, params);
    return cipher;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  static ShieldHeader _parseHeader(Uint8List encryptedBytes) {
    if (encryptedBytes.lengthInBytes < _magic.length + 2 + _ivLength + 1) {
      throw const FormatException('Encrypted asset is too short.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (encryptedBytes[i] != _magic[i]) {
        throw const FormatException('Invalid asset header.');
      }
    }

    final version = encryptedBytes[_magic.length];
    if (version == _version1) {
      final ivLength = encryptedBytes[_magic.length + 1];
      final ivStart = _magic.length + 2;
      final ivEnd = ivStart + ivLength;
      final iv = Uint8List.sublistView(encryptedBytes, ivStart, ivEnd);
      final cipherText = Uint8List.sublistView(encryptedBytes, ivEnd);
      return ShieldHeader(
        version: version,
        compressed: false,
        algorithm: _algoNone,
        originalLength: cipherText.length,
        iv: iv,
        cipherText: cipherText,
      );
    }

    if (version != _version2) {
      throw FormatException('Unsupported asset version: $version.');
    }

    if (encryptedBytes.lengthInBytes < _magic.length + 8 + _ivLength + 1) {
      throw const FormatException('Encrypted asset is too short.');
    }

    final flags = encryptedBytes[_magic.length + 1];
    final algo = encryptedBytes[_magic.length + 2];
    final ivLength = encryptedBytes[_magic.length + 3];
    final originalLength = _readUint32Le(encryptedBytes, _magic.length + 4);

    final ivStart = _magic.length + 8;
    final ivEnd = ivStart + ivLength;
    if (ivLength <= 0 || encryptedBytes.lengthInBytes < ivEnd + 1) {
      throw const FormatException('Invalid IV length.');
    }

    final iv = Uint8List.sublistView(encryptedBytes, ivStart, ivEnd);
    final cipherText = Uint8List.sublistView(encryptedBytes, ivEnd);

    return ShieldHeader(
      version: version,
      compressed: (flags & 0x01) != 0,
      algorithm: algo,
      originalLength: originalLength,
      iv: iv,
      cipherText: cipherText,
    );
  }

  static Uint8List _uint32le(int value) {
    return Uint8List.fromList(<int>[
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  static int _readUint32Le(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }
}

class ShieldHeader {
  ShieldHeader({
    required this.version,
    required this.compressed,
    required this.algorithm,
    required this.originalLength,
    required this.iv,
    required this.cipherText,
  });

  final int version;
  final bool compressed;
  final int algorithm;
  final int originalLength;
  final Uint8List iv;
  final Uint8List cipherText;
}
