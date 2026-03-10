import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_shield/asset_shield.dart';
import 'package:asset_shield/crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macos native decrypt', () {
    if (!Platform.isMacOS) {
      return;
    }

    final defaultPath = '../build/macos/libasset_shield_crypto.dylib';
    final dylibPath = Platform.environment['ASSET_SHIELD_DYLIB'] ?? defaultPath;
    if (!File(dylibPath).existsSync()) {
      return;
    }

    final key = ShieldKey.generate(lengthBytes: 32);
    final plain = Uint8List.fromList(List<int>.generate(256, (i) => i));
    final encrypted = ShieldCrypto.encrypt(plain, key);
    final decrypted = ShieldFfi.load(libraryPath: dylibPath).decrypt(encrypted, key);

    expect(decrypted, equals(plain));
  });
}
