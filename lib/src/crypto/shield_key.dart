import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Helpers for generating and encoding AES‑256 keys.
class ShieldKey {
  /// Decodes a base64 string into key bytes.
  static Uint8List fromBase64(String base64Key) {
    final bytes = base64.decode(base64Key.trim());
    return Uint8List.fromList(bytes);
  }

  /// Encodes key bytes as base64.
  static String toBase64(Uint8List keyBytes) {
    return base64.encode(keyBytes);
  }

  /// Generates a random 32‑byte AES‑256 key.
  static Uint8List generate({int lengthBytes = 32}) {
    if (lengthBytes != 32) {
      throw ArgumentError(
        'Key length must be 32 bytes for AES-256-GCM.',
      );
    }
    final random = Random.secure();
    final bytes = List<int>.generate(lengthBytes, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }
}
