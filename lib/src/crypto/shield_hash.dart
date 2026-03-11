import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

class ShieldHash {
  static String sha256Hex(String input) {
    final bytes = utf8.encode(input);
    final digest = crypto.sha256.convert(bytes).bytes;
    final buffer = StringBuffer();
    for (final b in digest) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
