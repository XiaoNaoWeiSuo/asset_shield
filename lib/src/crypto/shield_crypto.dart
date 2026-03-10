import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart'
    show AEADParameters, InvalidCipherTextException, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

class ShieldCrypto {
  static const List<int> _magic = <int>[0x41, 0x53, 0x53, 0x54];
  static const int _version = 1;
  static const int _ivLength = 12;
  static const int _tagLengthBytes = 16;

  static Uint8List encrypt(Uint8List plainBytes, Uint8List keyBytes) {
    _validateKeyLength(keyBytes);
    final iv = _randomBytes(_ivLength);
    final cipher = _initCipher(true, keyBytes, iv);
    final encrypted = cipher.process(plainBytes);

    final output = BytesBuilder(copy: false);
    output.add(_magic);
    output.add(<int>[_version, _ivLength]);
    output.add(iv);
    output.add(encrypted);
    return output.toBytes();
  }

  static Uint8List decrypt(Uint8List encryptedBytes, Uint8List keyBytes) {
    _validateKeyLength(keyBytes);
    if (encryptedBytes.lengthInBytes < _magic.length + 2 + _ivLength + 1) {
      throw const FormatException('Encrypted asset is too short.');
    }

    for (var i = 0; i < _magic.length; i++) {
      if (encryptedBytes[i] != _magic[i]) {
        throw const FormatException('Invalid asset header.');
      }
    }

    final version = encryptedBytes[_magic.length];
    if (version != _version) {
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
    if (length != 16 && length != 32) {
      throw ArgumentError(
        'Key length must be 16 or 32 bytes for AES-GCM.',
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
}
