import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_shield/crypto.dart';

void main() {
  test('encrypt/decrypt roundtrip', () {
    final key = ShieldKey.generate(lengthBytes: 32);
    final plain = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));
    final encrypted = ShieldCrypto.encrypt(plain, key);
    final decrypted = ShieldCrypto.decrypt(encrypted, key);

    expect(decrypted, equals(plain));
  });

  test('decrypt rejects invalid header', () {
    final key = ShieldKey.generate(lengthBytes: 32);
    final invalid = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7]);
    expect(() => ShieldCrypto.decrypt(invalid, key), throwsFormatException);
  });
}
