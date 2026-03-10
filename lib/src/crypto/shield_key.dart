import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class ShieldKey {
  static Uint8List fromBase64(String base64Key) {
    final bytes = base64.decode(base64Key.trim());
    return Uint8List.fromList(bytes);
  }

  static String toBase64(Uint8List keyBytes) {
    return base64.encode(keyBytes);
  }

  static Uint8List generate({int lengthBytes = 32}) {
    if (lengthBytes != 16 && lengthBytes != 32) {
      throw ArgumentError(
        'Key length must be 16 or 32 bytes for AES-GCM.',
      );
    }
    final random = Random.secure();
    final bytes = List<int>.generate(lengthBytes, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }
}
